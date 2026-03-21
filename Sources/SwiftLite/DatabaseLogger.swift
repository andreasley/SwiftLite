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
        case failedToFetch(sql: String)
        case loggerIsCloser
        
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
            case .failedToFetch(sql: let sql):
                return "Failed to fetch from database: \(sql)"
            case .loggerIsCloser:
                return "DatabaseLogger is already closed"
            }
        }
    }
    
    public enum OperationType: String, Sendable, Codable {
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
    public struct LogEntry: Equatable, Hashable, Sendable, Codable {
        public let id: UUID
        public let timestamp: Date
        public let transactionId: UUID
        public let operationType: OperationType
        public let tableName: String?
        public let objectId: UUID?
        public let columnName: String?
        public let newValue: SQLValue?
        public let metadata: String? // JSON-encoded additional data
        public let user: String?
        public let synchronizedIndex: Int64?
        
        public init(
            id: UUID = UUID(),
            timestamp: Date = Date(),
            transactionId: UUID,
            operationType: OperationType,
            tableName: String? = nil,
            objectId: UUID? = nil,
            columnName: String? = nil,
            newValue: SQLValue? = nil,
            metadata: String? = nil,
            user: String? = nil,
            synchronizedIndex: Int64? = nil
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
            self.user = user
            self.synchronizedIndex = synchronizedIndex
        }
    }
    
    private let connectionHandle: OpaquePointer
    private var isClosed = false
    private var isFetching = false
    public private(set) var fatalError: Swift.Error? {
        didSet {
            print("Fatal error in DatabaseLogger", fatalError?.localizedDescription ?? "")
        }
    }
    private let isFirstRun: Bool
    private let logFileURL: URL
    public let transport: SyncTransport
    public private(set) var highestSynchronizedIndex: Int64 = 0
    public private(set) var pendingLocalCount: Int64 = 0

    private(set) weak var database: Database!
    
    public init(transport: SyncTransport) async throws
    {
        guard await transport.localDatabaseLogUrl.isFileURL else {
            throw Error.failedToInitialize("Log URL must be a file URL")
        }
        
        self.logFileURL = await transport.localDatabaseLogUrl
        isFirstRun = !logFileURL.exists

        var pointer: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        
        let openStatus = sqlite3_open_v2(logFileURL.path, &pointer, flags, nil)
        
        guard let pointer, openStatus == SQLiteStatus.ok else {
            throw Error.failedToOpen(SQLiteStatus(openStatus))
        }
        
        self.connectionHandle = pointer
        self.transport = transport
        
        try initializeSchema()
        
        self.highestSynchronizedIndex = try getHighestSynchronizedIndex()
        self.pendingLocalCount = try getPendingLocalCount()

        print("📝 Database logger initialized at \(logFileURL.path)")
        print("Starting log from index \(self.highestSynchronizedIndex)")
        print("Number of unsynchronized log entries: \(self.pendingLocalCount)")
    }
    
    func setDatabase(_ database: Database) async
    {
        self.database = database

        await transport.registerIndexIncreaseCallback { [weak self] highestIndex in
            guard let self else { return }
            let highestSynchronizedIndex = await self.highestSynchronizedIndex
            guard highestIndex > highestSynchronizedIndex else { return }
            await self.fetchAndUpdate()
        }

        // Do initial sync here, so the most recent changes are already integrated into the database when the `Database` initializer completes
        await fetchAndUpdate()
    }
    
    private func fetchAndUpdate() async
    {
        guard !isFetching else { return }
        isFetching = true
        defer { isFetching = false }
        
        do {
            guard !isClosed else { throw Error.loggerIsCloser }

            // TODO: Stream these, so we're not stuck with 5GB of data on initial sync
            // TODO: publish progress information somewhere
            
            let newEntries = await transport.getEntries(from: highestSynchronizedIndex)

            print("Received \(newEntries.count) entries to apply")

            for entry in newEntries {
                try log(entry, source: .remote)
            }

            try await markOutdatedFieldUpdatesAsApplied()

            self.highestSynchronizedIndex = newEntries.compactMap { $0.synchronizedIndex }.reduce(highestSynchronizedIndex) { max($0, $1) }

            let entriesToApply = try await getEntriesToApply()
            
            // TODO: This might be slow for initial sync; do batches instead? Entries belonging to the same transaction should be sequential already.
            let groupedEntriesToApply = Dictionary(grouping: entriesToApply) { $0.transactionId }
            for (transactionId, entriesForTransaction) in groupedEntriesToApply.sorted(by: { ($0.value.first?.synchronizedIndex ?? 0) < ($1.value.first?.synchronizedIndex ?? 0) }) {
                let sortedEntriesForTransaction = entriesForTransaction.sorted(by: { ($0.synchronizedIndex ?? 0) < ($1.synchronizedIndex ?? 0) })
                try await database.processTransaction(entries: sortedEntriesForTransaction, transactionId: transactionId)
                try markEntriesAsAppliedLocally(transactionId: transactionId)
            }
        } catch {
            // If we can't successfully read/write to the log, the database can't be used
            try? await database.close()
            fatalError = error
        }
    }
    
    private func sendUnsynchronized() async
    {
        do {
            let entries = try await getEntriesToSend()
            print("Found \(entries.count) entries to send to sync")
            let updatedSynchronizationIndexes = await transport.sendEntries(entries: entries)
            if updatedSynchronizationIndexes.count != entries.count {
                print("Sent \(entries.count) to server but only recieved \(updatedSynchronizationIndexes.count) indexes")
            }
            try updateEntriesWithSynchronizationIndex(updatedSynchronizationIndexes)
            self.highestSynchronizedIndex = updatedSynchronizationIndexes.reduce(highestSynchronizedIndex) { max($0, $1.value) }
            print("Updated log to index \(self.highestSynchronizedIndex)")
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
            new_value ANY,
            metadata TEXT,
            user TEXT,
            synchronized_index INTEGER,
            applied_locally INTEGER NOT NULL DEFAULT 0
        ) STRICT;
        """
        
        let createIndexSQL = [
            "CREATE INDEX IF NOT EXISTS idx_timestamp ON operation_log(timestamp);",
            "CREATE INDEX IF NOT EXISTS idx_transaction_id ON operation_log(transaction_id);",
            "CREATE INDEX IF NOT EXISTS idx_operation_type ON operation_log(operation_type);",
            "CREATE INDEX IF NOT EXISTS idx_table_name ON operation_log(table_name);",
            "CREATE INDEX IF NOT EXISTS idx_object_id ON operation_log(object_id);",
            "CREATE INDEX IF NOT EXISTS idx_synchronized_index ON operation_log(synchronized_index);",
            "CREATE INDEX IF NOT EXISTS idx_applied_locally ON operation_log(applied_locally);"
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
    
    public nonisolated enum LogEntrySource {
        case local
        case remote
    }
    
    /// Log a single operation
    public func log(_ entry: LogEntry, source: LogEntrySource) throws {
        let sql = """
        INSERT OR IGNORE INTO operation_log (
            id, timestamp, transaction_id, operation_type,
            table_name, object_id, column_name, new_value, metadata,
            user, synchronized_index, applied_locally
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
        
        // Bind new_value column (index 8)
        if let newValue = entry.newValue {
            switch newValue {
            case .null:
                sqlite3_bind_null(statement, 8)
            case .int(let value):
                sqlite3_bind_int64(statement, 8, value)
            case .double(let value):
                sqlite3_bind_double(statement, 8, value)
            case .string(let value):
                sqlite3_bind_text(statement, 8, value, -1, SQLITE_TRANSIENT)
            case .data(let value):
                _ = value.withUnsafeBytes { bufferPointer in
                    sqlite3_bind_blob(statement, 8, bufferPointer.baseAddress, Int32(value.count), SQLITE_TRANSIENT)
                }
            }
        } else {
            sqlite3_bind_null(statement, 8)
        }
        
        // Bind metadata column (index 9)
        if let metadata = entry.metadata {
            sqlite3_bind_text(statement, 9, metadata, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, 9)
        }

        // Bind user column (index 10)
        if let user = entry.user {
            sqlite3_bind_text(statement, 10, user, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, 10)
        }
        
        // Bind synchronized_index column (index 11)
        if let synchronizedIndex = entry.synchronizedIndex {
            sqlite3_bind_int64(statement, 11, synchronizedIndex)
        } else {
            sqlite3_bind_null(statement, 11)
        }
        
        // Bind applied_locally column (index 12)
        sqlite3_bind_int64(statement, 12, source == .local ? 1 : 0)
        
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
                try log(entry, source: .local)
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }
    
    private func markEntriesAsAppliedLocally(transactionId: UUID) throws
    {
        let sql = """
        UPDATE operation_log 
        SET applied_locally = 1
        WHERE transaction_id = ?
        """
        
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(connectionHandle, sql, -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        
        guard let statement, prepareResult == SQLiteStatus.ok else {
            let errmsg = String(cString: sqlite3_errmsg(connectionHandle))
            throw Error.failedToLog(errmsg)
        }
        
        // Reset bindings for reuse
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)
        
        // Bind transaction_id (parameter 1)
        sqlite3_bind_text(statement, 1, transactionId.uuidString, -1, SQLITE_TRANSIENT)
        
        // Execute the update
        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_DONE else {
            let errmsg = String(cString: sqlite3_errmsg(connectionHandle))
            throw Error.failedToLog("Failed to mark entries as applied locally: \(errmsg)")
        }
    }

    private func updateEntriesWithSynchronizationIndex(_ updatedIndexes: [UUID: Int64]) throws
    {
        guard !updatedIndexes.isEmpty else { return }
        
        let sql = """
        UPDATE operation_log 
        SET synchronized_index = ?
        WHERE id = ?
        """
        
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(connectionHandle, sql, -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        
        guard let statement, prepareResult == SQLiteStatus.ok else {
            let errmsg = String(cString: sqlite3_errmsg(connectionHandle))
            throw Error.failedToLog(errmsg)
        }
        
        // Begin transaction for batch updates
        try execute("BEGIN")
        
        do {
            for (entryId, synchronizedIndex) in updatedIndexes {
                // Reset bindings for reuse
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                
                // Bind synchronized_index (parameter 1)
                sqlite3_bind_int64(statement, 1, synchronizedIndex)
                
                // Bind entry id (parameter 2)
                sqlite3_bind_text(statement, 2, entryId.uuidString, -1, SQLITE_TRANSIENT)
                
                // Execute the update
                let stepResult = sqlite3_step(statement)
                guard stepResult == SQLITE_DONE else {
                    let errmsg = String(cString: sqlite3_errmsg(connectionHandle))
                    throw Error.failedToLog("Failed to update synchronized_index: \(errmsg)")
                }
            }
            
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }
    
    /// Get the highest synchronized_index value from the log table
    /// Returns nil if no entries have a synchronized_index set
    public func getHighestSynchronizedIndex() throws -> Int64
    {
        let sql = "SELECT MAX(synchronized_index) FROM operation_log"
        
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(connectionHandle, sql, -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        
        guard let statement, prepareResult == SQLiteStatus.ok else {
            let errmsg = String(cString: sqlite3_errmsg(connectionHandle))
            throw Error.failedToLog(errmsg)
        }
        
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw Error.failedToFetch(sql: sql)
        }
        
        // Check if the result is NULL (no entries with synchronized_index) = fresh database
        if sqlite3_column_type(statement, 0) == SQLITE_NULL {
            return 0
        }
        
        return sqlite3_column_int64(statement, 0)
    }

    public func getPendingLocalCount() throws -> Int64
    {
        let sql = "SELECT COUNT(*) FROM operation_log WHERE synchronized_index IS NULL"
        
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(connectionHandle, sql, -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        
        guard let statement, prepareResult == SQLiteStatus.ok else {
            let errmsg = String(cString: sqlite3_errmsg(connectionHandle))
            throw Error.failedToLog(errmsg)
        }
        
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw Error.failedToFetch(sql: sql)
        }
        
        // Check if the result is NULL (no entries with synchronized_index) = fresh database
        if sqlite3_column_type(statement, 0) == SQLITE_NULL {
            return 0
        }
        
        return sqlite3_column_int64(statement, 0)
    }

    
    /// Log a complete transaction's worth of changes in a single batch operation.
    /// This is more efficient than calling individual log methods.
    /// - Parameters:
    ///   - transactionId: The UUID of the transaction
    ///   - schemaChanges: Schema changes to log (table/column/index operations)
    ///   - dataChanges: Data changes to log (row create/update/delete operations)
    public func logTransactionBatch(
        transactionId: UUID,
        schemaChanges: [SchemaChange],
        dataChanges: [ChangedObject]
    ) async throws {
        var entries: [LogEntry] = []
        
        // Convert schema changes to log entries
        for schemaChange in schemaChanges {
            var metadataJSON: String?
            if let metadata = schemaChange.metadata {
                if let jsonData = try? JSONSerialization.data(withJSONObject: metadata),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    metadataJSON = jsonString
                }
            }
            
            entries.append(LogEntry(
                transactionId: transactionId,
                operationType: schemaChange.operationType,
                tableName: schemaChange.tableName,
                columnName: schemaChange.columnName,
                metadata: metadataJSON
            ))
        }
        
        // Convert data changes to log entries
        for change in dataChanges {
            switch change.status {
            case .created:
                // Log the row creation
                entries.append(LogEntry(
                    transactionId: transactionId,
                    operationType: .rowCreated,
                    tableName: change.table,
                    objectId: change.objectId
                ))
                
                // Log each field value as a separate field update
                if let updatedFields = change.updatedFields {
                    for (fieldName, value) in updatedFields {
                        entries.append(LogEntry(
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
                entries.append(LogEntry(
                    transactionId: transactionId,
                    operationType: .rowDeleted,
                    tableName: change.table,
                    objectId: change.objectId
                ))
                
            case .updated:
                // Log each field change separately
                if let updatedFields = change.updatedFields {
                    for (fieldName, newValue) in updatedFields {
                        entries.append(LogEntry(
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
        
        // Log all entries in a single batch
        try logBatch(entries)
        
        Task {
            await sendUnsynchronized()
        }
    }
    
    /// Represents a schema change operation to be logged
    public struct SchemaChange: Sendable {
        public let operationType: OperationType
        public let tableName: String
        public let columnName: String?
        public let metadata: [String: any Sendable]?
        
        public init(
            operationType: OperationType,
            tableName: String,
            columnName: String? = nil,
            metadata: [String: any Sendable]? = nil
        ) {
            self.operationType = operationType
            self.tableName = tableName
            self.columnName = columnName
            self.metadata = metadata
        }
    }
    
    private func getEntriesToSend() async throws -> [LogEntry]
    {
        let sql = """
        SELECT 
            id, timestamp, transaction_id, operation_type,
            table_name, object_id, column_name, new_value, metadata,
            user, synchronized_index
        FROM operation_log
        WHERE synchronized_index IS NULL
        ORDER BY timestamp ASC
        """
        
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(connectionHandle, sql, -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        
        guard let statement, prepareResult == SQLiteStatus.ok else {
            let errmsg = String(cString: sqlite3_errmsg(connectionHandle))
            throw Error.failedToLog(errmsg)
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
            
            // Read new_value from column index 7
            let newValue: SQLValue?
            if sqlite3_column_type(statement, 7) != SQLITE_NULL {
                let columnType = sqlite3_column_type(statement, 7)
                switch columnType {
                case SQLITE_INTEGER:
                    newValue = .int(sqlite3_column_int64(statement, 7))
                case SQLITE_FLOAT:
                    newValue = .double(sqlite3_column_double(statement, 7))
                case SQLITE_TEXT:
                    newValue = .string(String(cString: sqlite3_column_text(statement, 7)))
                case SQLITE_BLOB:
                    if let blobPointer = sqlite3_column_blob(statement, 7) {
                        let blobSize = Int(sqlite3_column_bytes(statement, 7))
                        let data = Data(bytes: blobPointer, count: blobSize)
                        newValue = .data(data)
                    } else {
                        newValue = nil
                    }
                case SQLITE_NULL:
                    newValue = .null
                default:
                    newValue = nil
                }
            } else {
                newValue = nil
            }
            
            // Read metadata from column index 8
            let metadata = sqlite3_column_type(statement, 8) != SQLITE_NULL
                ? String(cString: sqlite3_column_text(statement, 8))
                : nil
            
            // Read user from column index 9
            let user = sqlite3_column_type(statement, 9) != SQLITE_NULL
                ? String(cString: sqlite3_column_text(statement, 9))
                : nil
            
            // Read synchronized_index from column index 10
            let synchronizedIndex = sqlite3_column_type(statement, 10) != SQLITE_NULL
                ? sqlite3_column_int64(statement, 10)
                : nil
                        
            entries.append(LogEntry(
                id: id,
                timestamp: timestamp,
                transactionId: transactionId,
                operationType: operationType,
                tableName: tableName,
                objectId: objectId,
                columnName: columnName,
                newValue: newValue,
                metadata: metadata,
                user: user,
                synchronizedIndex: synchronizedIndex
            ))
        }
        
        return entries
    }
    
    public func markOutdatedFieldUpdatesAsApplied() async throws
    {
        // There's no point in ever applying field update values for a specific table/object/column if there's already a more recent value.
        // Mark all such outdated values as "applied_locally = 1". These won't be applied to the local database. This works fine, even if they were part of a transaction, as all fields are nullable and foreign key checks are disabled while replaying (so setting a reference in a later transaction isn't an issue).
        
        let sql = """
        UPDATE operation_log
        SET applied_locally = 1
        WHERE id IN (
            SELECT id
            FROM (
                SELECT id,
                       ROW_NUMBER() OVER (
                           PARTITION BY table_name, object_id, column_name 
                           ORDER BY timestamp DESC
                       ) as rn
                FROM operation_log
                WHERE operation_type = 'field_updated'
                  AND applied_locally = 0
            )
            WHERE rn > 1
        )
        """
        
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(connectionHandle, sql, -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        
        guard let statement, prepareResult == SQLiteStatus.ok else {
            let errmsg = String(cString: sqlite3_errmsg(connectionHandle))
            throw Error.failedToLog("Failed to mark outdated field updates: \(errmsg)")
        }
        
        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_DONE else {
            let errmsg = String(cString: sqlite3_errmsg(connectionHandle))
            throw Error.failedToLog("Failed to execute mark outdated field updates: \(errmsg)")
        }
        
        let changedRows = sqlite3_changes(connectionHandle)
        if changedRows > 0 {
            print("Marked \(changedRows) outdated field update(s) as applied")
        }
    }

    public func getEntriesToApply() async throws -> [LogEntry]
    {
        let sql = """
        SELECT 
            id, timestamp, transaction_id, operation_type,
            table_name, object_id, column_name, new_value, metadata,
            user, synchronized_index
        FROM operation_log
            WHERE applied_locally = 0
        ORDER BY timestamp ASC
        """
        
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(connectionHandle, sql, -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        
        guard let statement, prepareResult == SQLiteStatus.ok else {
            let errmsg = String(cString: sqlite3_errmsg(connectionHandle))
            throw Error.failedToLog(errmsg)
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
            
            // Read new_value from column index 7
            let newValue: SQLValue?
            if sqlite3_column_type(statement, 7) != SQLITE_NULL {
                let columnType = sqlite3_column_type(statement, 7)
                switch columnType {
                case SQLITE_INTEGER:
                    newValue = .int(sqlite3_column_int64(statement, 7))
                case SQLITE_FLOAT:
                    newValue = .double(sqlite3_column_double(statement, 7))
                case SQLITE_TEXT:
                    newValue = .string(String(cString: sqlite3_column_text(statement, 7)))
                case SQLITE_BLOB:
                    if let blobPointer = sqlite3_column_blob(statement, 7) {
                        let blobSize = Int(sqlite3_column_bytes(statement, 7))
                        let data = Data(bytes: blobPointer, count: blobSize)
                        newValue = .data(data)
                    } else {
                        newValue = nil
                    }
                case SQLITE_NULL:
                    newValue = .null
                default:
                    newValue = nil
                }
            } else {
                newValue = nil
            }
            
            // Read metadata from column index 8
            let metadata = sqlite3_column_type(statement, 8) != SQLITE_NULL
                ? String(cString: sqlite3_column_text(statement, 8))
                : nil
            
            // Read user from column index 9
            let user = sqlite3_column_type(statement, 9) != SQLITE_NULL
                ? String(cString: sqlite3_column_text(statement, 9))
                : nil
            
            // Read synchronized_index from column index 10
            let synchronizedIndex = sqlite3_column_type(statement, 10) != SQLITE_NULL
                ? sqlite3_column_int64(statement, 10)
                : nil
            
            entries.append(LogEntry(
                id: id,
                timestamp: timestamp,
                transactionId: transactionId,
                operationType: operationType,
                tableName: tableName,
                objectId: objectId,
                columnName: columnName,
                newValue: newValue,
                metadata: metadata,
                user: user,
                synchronizedIndex: synchronizedIndex
            ))
        }
        
        return entries
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
