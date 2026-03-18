import Foundation
import SQLite3

/// Manages a separate SQLite database for logging all database operations.
/// This log is essential for distributed sync, providing a complete audit trail
/// of all schema changes and data modifications with timestamps and transaction IDs.
/// Only successful transactions are logged - failed/rolled back transactions are not recorded.
public actor DatabaseLogger
{
    public enum Error: LocalizedError {
        case failedToOpen(SQLiteStatus)
        case failedToClose(SQLiteStatus)
        case failedToInitialize(String)
        case failedToLog(String)
        
        public var errorDescription: String? {
            switch self {
            case .failedToOpen(let status):
                return "Failed to open log database: \(status.description)"
            case .failedToClose(let status):
                return "Failed to close log database: \(status.description)"
            case .failedToInitialize(let message):
                return "Failed to initialize log database: \(message)"
            case .failedToLog(let message):
                return "Failed to log operation: \(message)"
            }
        }
    }
    
    public enum OperationType: String, Sendable {
        // Schema operations
        case tableCreated = "table_created"
        case columnAdded = "column_added"
        case indexCreated = "index_created"
        case indexDropped = "index_dropped"
        
        // Data operations
        case rowCreated = "row_created"
        case rowDeleted = "row_deleted"
        case fieldUpdated = "field_updated"
    }
    
    /// Represents a single log entry in the database history
    public struct LogEntry: Equatable, Hashable, Sendable {
        public let id: UUID
        public let timestamp: Date
        public let transactionId: UUID
        public let operationType: OperationType
        public let tableName: String?
        public let objectId: UUID?
        public let columnName: String?
        public let newValue: SQLValue?
        public let metadata: String? // JSON-encoded additional data
        
        public init(
            id: UUID = UUID(),
            timestamp: Date = Date(),
            transactionId: UUID,
            operationType: OperationType,
            tableName: String? = nil,
            objectId: UUID? = nil,
            columnName: String? = nil,
            newValue: SQLValue? = nil,
            metadata: String? = nil
        ) {
            self.id = id
            self.timestamp = timestamp
            self.transactionId = transactionId
            self.operationType = operationType
            self.tableName = tableName
            self.objectId = objectId
            self.columnName = columnName
            self.newValue = newValue
            self.metadata = metadata
        }
    }
    
    private let connectionHandle: OpaquePointer
    private var isClosed = false
    public private(set) var fatalError: Swift.Error?
    private let isFirstRun: Bool
    private let logFileURL: URL
    private let transport: SyncTransport

    private(set) weak var database: Database!
    
    public init(transport: SyncTransport) async throws
    {
        guard await transport.localDatabaseLogUrl.isFileURL else {
            throw Error.failedToInitialize("Log URL must be a file URL")
        }
        
        isFirstRun = !logFileURL.exists
        
        self.logFileURL = await transport.localDatabaseLogUrl
        
        var pointer: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        
        let openStatus = sqlite3_open_v2(logFileURL.path, &pointer, flags, nil)
        
        guard let pointer, openStatus == SQLiteStatus.ok else {
            throw Error.failedToOpen(SQLiteStatus(openStatus))
        }
        
        self.connectionHandle = pointer
        
        try initializeSchema()
        
        await transport.registerIndexIncreaseCallback { [weak self] highestIndex in
            Task {
                guard let self else { return }
                await self.fetchAndUpdate()
            }
        }
        
        print("📝 Database logger initialized at \(logFileURL.path)")
    }
    
    func setDatabase(_ database: Database) async
    {
        self.database = database

        // Do initial sync here, so the most recent changes are already integrated into the database when the `Database` initializer completes
        await fetchAndUpdate()
    }
    
    private func fetchAndUpdate() async
    {
        do {
            // TODO: Stream these, so we're not stuck with 5GB of data on initial sync
            
            let newEntries = await transport.getEntries(from: 0)
            for entry in newEntries {
                try log(entry)
            }
            
            // TODO: Save entries to local table
            
            guard !isClosed else {
                // Not an issue; update the database next time
                return
            }
            
            let entriesToApply = try await getEntriesToApply()
            
            // TODO: This might be slow for initial sync; do batches instead? Entries belonging to the same transaction should be sequential already.
            let groupedEntriesToApply = Dictionary(grouping: entriesToApply) { $0.transactionId }
            for (transactionId, entriesForTransaction) in groupedEntriesToApply.sorted(by: { $0.value.first!.timestamp < $1.value.first!.timestamp }) {
                try await database.processTransaction(entries: entriesForTransaction, transactionId: transactionId)
            }
        } catch {
            // If we can't successfully read/write to the log, the database can't be used
            try? await database.close()
            fatalError = error
        }
    }
    
    /// Creates the log table schema if it doesn't exist
    private func initializeSchema() throws {
        let createTableSQL = """
        CREATE TABLE IF NOT EXISTS operation_log (
            id TEXT PRIMARY KEY NOT NULL,
            timestamp REAL NOT NULL,
            transaction_id TEXT NOT NULL,
            operation_type TEXT NOT NULL,
            table_name TEXT,
            object_id TEXT,
            column_name TEXT,
            metadata TEXT
        ) STRICT;
        """
        
        let createIndexSQL = [
            "CREATE INDEX IF NOT EXISTS idx_timestamp ON operation_log(timestamp);",
            "CREATE INDEX IF NOT EXISTS idx_transaction_id ON operation_log(transaction_id);",
            "CREATE INDEX IF NOT EXISTS idx_operation_type ON operation_log(operation_type);",
            "CREATE INDEX IF NOT EXISTS idx_table_name ON operation_log(table_name);",
            "CREATE INDEX IF NOT EXISTS idx_object_id ON operation_log(object_id);"
        ]
        
        try execute(createTableSQL)
        
        for indexSQL in createIndexSQL {
            try execute(indexSQL)
        }
    }
    
    /// Execute a SQL statement without parameters
    private func execute(_ sql: String) throws {
        let result = sqlite3_exec(connectionHandle, sql, nil, nil, nil)
        guard result == SQLiteStatus.ok else {
            let errmsg = String(cString: sqlite3_errmsg(connectionHandle))
            throw Error.failedToInitialize(errmsg)
        }
    }
    
    /// Log a single operation
    public func log(_ entry: LogEntry) throws {
        let sql = """
        INSERT INTO operation_log (
            id, timestamp, transaction_id, operation_type,
            table_name, object_id, column_name, metadata
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """
        
        var statement: OpaquePointer?
        
        let prepareResult = sqlite3_prepare_v2(connectionHandle, sql, -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        
        guard let statement, prepareResult == SQLiteStatus.ok else {
            let errmsg = String(cString: sqlite3_errmsg(connectionHandle))
            throw Error.failedToLog(errmsg)
        }
        
        // Bind values
        sqlite3_bind_text(statement, 1, entry.id.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(statement, 2, entry.timestamp.timeIntervalSince1970)
        sqlite3_bind_text(statement, 3, entry.transactionId.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 4, entry.operationType.rawValue, -1, SQLITE_TRANSIENT)
        
        if let tableName = entry.tableName {
            sqlite3_bind_text(statement, 5, tableName, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, 5)
        }
        
        if let objectId = entry.objectId {
            sqlite3_bind_text(statement, 6, objectId.uuidString, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, 6)
        }
        
        if let columnName = entry.columnName {
            sqlite3_bind_text(statement, 7, columnName, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, 7)
        }
        
        // For field_updated operations, store the value in metadata column
        // For other operations, use metadata for its original purpose (schema metadata, etc.)
        if entry.operationType == .fieldUpdated {
            // Store the SQLValue in metadata column
            if let newValue = entry.newValue {
                let encoder = JSONEncoder()
                if let jsonData = try? encoder.encode(newValue),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    sqlite3_bind_text(statement, 8, jsonString, -1, SQLITE_TRANSIENT)
                } else {
                    sqlite3_bind_null(statement, 8)
                }
            } else {
                sqlite3_bind_null(statement, 8)
            }
        } else {
            // metadata contains schema metadata or other info
            if let metadata = entry.metadata {
                sqlite3_bind_text(statement, 8, metadata, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(statement, 8)
            }
        }
        
        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_DONE else {
            let errmsg = String(cString: sqlite3_errmsg(connectionHandle))
            throw Error.failedToLog(errmsg)
        }
    }
    
    /// Log multiple operations in a batch (more efficient for large changesets)
    public func logBatch(_ entries: [LogEntry]) throws {
        try execute("BEGIN")
        
        do {
            for entry in entries {
                try log(entry)
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }
    
    /// Log schema change operations
    public func logSchemaChange(
        transactionId: UUID,
        operationType: OperationType,
        tableName: String,
        columnName: String? = nil,
        metadata: [String: Any]? = nil
    ) throws {
        var metadataJSON: String?
        if let metadata {
            if let jsonData = try? JSONSerialization.data(withJSONObject: metadata),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                metadataJSON = jsonString
            }
        }
        
        try log(LogEntry(
            transactionId: transactionId,
            operationType: operationType,
            tableName: tableName,
            columnName: columnName,
            metadata: metadataJSON
        ))
    }
    
    /// Log data change from a ChangedObject (granular field-level logging)
    public func logDataChange(
        transactionId: UUID,
        change: ChangedObject
    ) throws {
        switch change.status {
        case .created:
            // Log the row creation
            try log(LogEntry(
                transactionId: transactionId,
                operationType: .rowCreated,
                tableName: change.table,
                objectId: change.objectId
            ))
            
            // Log each field value as a separate field update
            if let updatedFields = change.updatedFields {
                for (fieldName, value) in updatedFields {
                    try log(LogEntry(
                        transactionId: transactionId,
                        operationType: .fieldUpdated,
                        tableName: change.table,
                        objectId: change.objectId,
                        columnName: fieldName,
                        newValue: value
                    ))
                }
            }
            
        case .deleted:
            // Log the row deletion
            try log(LogEntry(
                transactionId: transactionId,
                operationType: .rowDeleted,
                tableName: change.table,
                objectId: change.objectId
            ))
            
        case .updated:
            // Log each field change separately
            if let updatedFields = change.updatedFields {
                for (fieldName, newValue) in updatedFields {
                    try log(LogEntry(
                        transactionId: transactionId,
                        operationType: .fieldUpdated,
                        tableName: change.table,
                        objectId: change.objectId,
                        columnName: fieldName,
                        newValue: newValue
                    ))
                }
            }
        }
    }
    
    public func getEntriesToApply() async throws -> [LogEntry]
    {
        // TODO: Get all entries marked applied_locally == false that are either 1) Schema upgrade entries or 2) the most recent value update entry for a specific table and field
    }

        
        /// Retrieve log entries within a date range
    public func getEntries(
        from startDate: Date? = nil,
        to endDate: Date? = nil,
        transactionId: UUID? = nil,
        tableName: String? = nil,
        limit: Int? = nil
    ) throws -> [LogEntry] {
        var sql = "SELECT * FROM operation_log WHERE 1=1"
        var bindIndex: Int32 = 1
        
        if startDate != nil {
            sql += " AND timestamp >= ?"
        }
        if endDate != nil {
            sql += " AND timestamp <= ?"
        }
        if transactionId != nil {
            sql += " AND transaction_id = ?"
        }
        if tableName != nil {
            sql += " AND table_name = ?"
        }
        
        sql += " ORDER BY timestamp ASC"
        
        if let limit {
            sql += " LIMIT \(limit)"
        }
        
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(connectionHandle, sql, -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        
        guard let statement, prepareResult == SQLiteStatus.ok else {
            let errmsg = String(cString: sqlite3_errmsg(connectionHandle))
            throw Error.failedToLog(errmsg)
        }
        
        // Bind parameters
        if let startDate {
            sqlite3_bind_double(statement, bindIndex, startDate.timeIntervalSince1970)
            bindIndex += 1
        }
        if let endDate {
            sqlite3_bind_double(statement, bindIndex, endDate.timeIntervalSince1970)
            bindIndex += 1
        }
        if let transactionId {
            sqlite3_bind_text(statement, bindIndex, transactionId.uuidString, -1, SQLITE_TRANSIENT)
            bindIndex += 1
        }
        if let tableName {
            sqlite3_bind_text(statement, bindIndex, tableName, -1, SQLITE_TRANSIENT)
            bindIndex += 1
        }
        
        var entries: [LogEntry] = []
        
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = UUID(uuidString: String(cString: sqlite3_column_text(statement, 0))),
                  let transactionId = UUID(uuidString: String(cString: sqlite3_column_text(statement, 2))),
                  let operationType = OperationType(rawValue: String(cString: sqlite3_column_text(statement, 3)))
            else {
                continue
            }
            
            let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(statement, 1))
            
            let tableName = sqlite3_column_type(statement, 4) != SQLITE_NULL
                ? String(cString: sqlite3_column_text(statement, 4))
                : nil
            
            let objectId = sqlite3_column_type(statement, 5) != SQLITE_NULL
                ? UUID(uuidString: String(cString: sqlite3_column_text(statement, 5)))
                : nil
            
            let columnName = sqlite3_column_type(statement, 6) != SQLITE_NULL
                ? String(cString: sqlite3_column_text(statement, 6))
                : nil
            
            // For field_updated operations, read from metadata column
            // For other operations, metadata contains schema metadata or other info
            let newValue: SQLValue?
            let metadata: String?
            
            if operationType == .fieldUpdated {
                // Read value from metadata column (column index 7)
                if sqlite3_column_type(statement, 7) != SQLITE_NULL {
                    let jsonString = String(cString: sqlite3_column_text(statement, 7))
                    let decoder = JSONDecoder()
                    if let jsonData = jsonString.data(using: .utf8),
                       let sqlValue = try? decoder.decode(SQLValue.self, from: jsonData) {
                        newValue = sqlValue
                    } else {
                        newValue = nil
                    }
                } else {
                    newValue = nil
                }
                metadata = nil // metadata is used for the value, not for metadata itself
            } else {
                // For other operation types, use original behavior
                newValue = nil
                
                metadata = sqlite3_column_type(statement, 7) != SQLITE_NULL
                    ? String(cString: sqlite3_column_text(statement, 7))
                    : nil
            }
            
            entries.append(LogEntry(
                id: id,
                timestamp: timestamp,
                transactionId: transactionId,
                operationType: operationType,
                tableName: tableName,
                objectId: objectId,
                columnName: columnName,
                newValue: newValue,
                metadata: metadata
            ))
        }
        
        return entries
    }
    
    /// Get all transactions within a date range
    public func getTransactions(
        from startDate: Date? = nil,
        to endDate: Date? = nil
    ) throws -> [UUID] {
        var sql = "SELECT DISTINCT transaction_id FROM operation_log WHERE 1=1"
        var bindIndex: Int32 = 1
        
        if startDate != nil {
            sql += " AND timestamp >= ?"
        }
        if endDate != nil {
            sql += " AND timestamp <= ?"
        }
        
        sql += " ORDER BY timestamp ASC"
        
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(connectionHandle, sql, -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        
        guard let statement, prepareResult == SQLiteStatus.ok else {
            let errmsg = String(cString: sqlite3_errmsg(connectionHandle))
            throw Error.failedToLog(errmsg)
        }
        
        if let startDate {
            sqlite3_bind_double(statement, bindIndex, startDate.timeIntervalSince1970)
            bindIndex += 1
        }
        if let endDate {
            sqlite3_bind_double(statement, bindIndex, endDate.timeIntervalSince1970)
            bindIndex += 1
        }
        
        var transactionIds: [UUID] = []
        
        while sqlite3_step(statement) == SQLITE_ROW {
            if let transactionId = UUID(uuidString: String(cString: sqlite3_column_text(statement, 0))) {
                transactionIds.append(transactionId)
            }
        }
        
        return transactionIds
    }
    
    /// Close the log database
    public func close() throws {
        guard !isClosed else { return }
        
        let result = sqlite3_close(connectionHandle)
        
        guard result == SQLiteStatus.ok else {
            throw Error.failedToClose(SQLiteStatus(result))
        }
        
        isClosed = true
        print("📝 Database logger closed")
    }
    
    isolated deinit {
        if !isClosed {
            sqlite3_close(connectionHandle)
        }
    }
}
