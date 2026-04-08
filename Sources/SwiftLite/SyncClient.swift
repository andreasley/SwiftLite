import Foundation
import SQLite3

/// Manages a separate SQLite database for logging all database operations.
/// This log is essential for distributed sync, providing a complete audit trail
/// of all schema changes and data modifications with timestamps and transaction IDs.
/// Only successful transactions are logged - failed/rolled back transactions are not recorded.
public actor SyncClient
{
    public enum Error: LocalizedError {
        case failedToOpen(SQLiteStatus)
        case failedToClose(SQLiteStatus)
        case failedToInitialize(String)
        case failedToLog(String)
        case failedToFetch(sql: String)
        case failedToFindDatabaseId
        case databaseIdForNameNotReceived
        case failedToGetConfigurationValue(String)
        case databaseIfDoesNotMatch
        case failedToReadSyncDetailsFromConfiguration
        
        public var errorDescription: String? {
            return switch self {
            case .failedToOpen(let status):
                "Failed to open log database: \(status.description)"
            case .failedToClose(let status):
                "Failed to close log database: \(status.description)"
            case .failedToInitialize(let message):
                "Failed to initialize log database: \(message)"
            case .failedToLog(let message):
                "Failed to log operation: \(message)"
            case .failedToFetch(sql: let sql):
                "Failed to fetch from database: \(sql)"
            case .failedToFindDatabaseId:
                "The sync endpoint is offline and no local database exists."
            case .failedToGetConfigurationValue(let key):
                "Failed to get configuration value '\(key)'"
            case .databaseIdForNameNotReceived:
                "Database ID for the provided database name was not returned from the server."
            case .databaseIfDoesNotMatch:
                "The server returned a different database ID than the expected one. The server database may have been reset or removed."
            case .failedToReadSyncDetailsFromConfiguration:
                "Failed to read sync details from configuration"
            }
        }
    }
    
    public nonisolated struct Status: Sendable, Equatable
    {
        var isFullySynchronized: Bool {
            pendingLocalChanges == 0 && pendingRemoteChanges == 0
        }
        
        public let connectorStatus: SyncConnectorStatus
        public let currentSyncProgress: Progress?
        public let pendingLocalChanges: Int64
        public let pendingRemoteChanges: Int64
        public let highestSyncedLocalIndex: Int64
//        let syncHistory: [SyncHistoryEntry]
        public let fatalError: Swift.Error?
        
        init(
            connectorStatus: SyncConnectorStatus,
            currentSyncProgress: Progress? = nil,
            pendingLocalChanges: Int64 = 0,
            pendingRemoteChanges: Int64 = 0,
            highestSyncedLocalIndex: Int64 = 0,
            fatalError: Swift.Error? = nil
        ) {
            self.connectorStatus = connectorStatus
            self.currentSyncProgress = currentSyncProgress
            self.pendingLocalChanges = pendingLocalChanges
            self.pendingRemoteChanges = pendingRemoteChanges
            self.highestSyncedLocalIndex = highestSyncedLocalIndex
            self.fatalError = fatalError
        }
        
        public static func == (lhs: Status, rhs: Status) -> Bool {
            // Compare all equatable properties
            // Note: Progress and Error cannot be compared directly, so we compare what we can
            lhs.connectorStatus == rhs.connectorStatus &&
            lhs.pendingLocalChanges == rhs.pendingLocalChanges &&
            lhs.pendingRemoteChanges == rhs.pendingRemoteChanges &&
            lhs.highestSyncedLocalIndex == rhs.highestSyncedLocalIndex &&
            lhs.currentSyncProgress?.totalUnitCount == rhs.currentSyncProgress?.totalUnitCount &&
            lhs.currentSyncProgress?.completedUnitCount == rhs.currentSyncProgress?.completedUnitCount &&
            lhs.fatalError?.localizedDescription == rhs.fatalError?.localizedDescription
        }
    }
    
    
    
    private let connectionHandle: OpaquePointer
    private var isClosed = false
    private var isSyncing = false
    public private(set) var fatalError: Swift.Error? {
        didSet {
            print("Fatal error in SyncClient", fatalError?.localizedDescription ?? "")
        }
    }
    private let shouldCreateDatabase: Bool
    private let databaseFileUrl: URL?
    private let persistedConfiguration: PersistedConfiguration
    
    public let connector: SyncConnector
    
    public private(set) var highestSyncedLocalIndex: Int64 = 0 { didSet { updateStatus() }}
    public private(set) var highestRemoteIndex: Int64? { didSet { updateStatus() }}
    public private(set) var pendingLocalCount: Int64 = 0 { didSet { updateStatus() }}
    public private(set) var currentSyncProgress: Progress? { didSet { updateStatus() }}

    public var pendingRemoteCount: Int64? {
        guard let highestRemoteIndex else { return 0 }
        return highestRemoteIndex - highestSyncedLocalIndex
    }

    // Status stream support
    private var status: Status
    private var connectorStatus: SyncConnectorStatus
    private var statusContinuation: AsyncStream<Status>.Continuation
    public nonisolated let statusStream: AsyncStream<Status>

    private(set) weak var database: Database!
    
    private let gate = TransactionGate()
    
    public init(connector: SyncConnector, databaseStorage: Database.StorageType) async throws
    {
        var flags = [SQLITE_OPEN_READWRITE, SQLITE_OPEN_CREATE, SQLITE_OPEN_FULLMUTEX]

        switch databaseStorage {
        case .file(let url):
            let urlForSyncDatabase = url.deletingPathExtension().appendingPathExtension("sync.sqlite")
            shouldCreateDatabase = !urlForSyncDatabase.exists
            databaseFileUrl = urlForSyncDatabase
        case .inMemory:
            shouldCreateDatabase = true
            databaseFileUrl = nil
            flags.append(SQLITE_OPEN_MEMORY)
        }
        
        // As long as the log file exists, the database file can be created by replaying the log file. However, if the log file is missing, this must be a new (or broken) database that can't be opened if the sync endpoint isn't online.

        var pointer: OpaquePointer?
        
        let openStatus = sqlite3_open_v2(databaseFileUrl?.filePath, &pointer, flags.reduce(0, |), nil)
        
        guard let pointer, openStatus == SQLiteStatus.ok else {
            throw Error.failedToOpen(SQLiteStatus(openStatus))
        }
        
        let persistedConfiguration = PersistedConfiguration(tableName: "configuration", connectionHandle: pointer)

        if shouldCreateDatabase {
            try Self.initializeSchema(connectionHandle: pointer)
            try persistedConfiguration.setDefaultValues()
        }
        
        let databaseId: UUID
        
        if try persistedConfiguration.didSuccessfullySyncSometime {
            // This sync database has been used before. The SyncClient can initialize, regardless of connectivity.
            // However, if there is connectivity and the servers provides a different database ID for the database name, the server-side database has probably been reset. No syncing is possible in this case and the initializer shouldn't complete.
            guard let previousDatabaseId = try persistedConfiguration.getServerDatabaseId() else {
                throw Error.failedToReadSyncDetailsFromConfiguration
            }
            databaseId = previousDatabaseId
            
            if let currentDatabaseId = try? await connector.getDatabaseId() {
                guard currentDatabaseId == previousDatabaseId else {
                    throw Error.databaseIfDoesNotMatch
                }
            } else {
                // Connectivity probably failed; stay in offline mode and try again later. The database ID will be checked on each request, so the sync may fail later, but there's no way to know this yet.
            }
        } else {
            // This is a new database. Its ID is not yet known. Initialization of the SyncClient requires connectivity.
            guard let newDatabaseId = try await connector.getDatabaseId() else {
                throw Error.databaseIdForNameNotReceived
            }
            databaseId = newDatabaseId
            try persistedConfiguration.setServerDatabaseId(newDatabaseId)
        }
        
        (statusStream, statusContinuation) = AsyncStream.makeStream(of: Status.self)

        self.persistedConfiguration = persistedConfiguration
        self.connectionHandle = pointer
        self.connector = connector
        self.connectorStatus = await connector.status
        self.status = Status(connectorStatus: self.connectorStatus)
        self.highestSyncedLocalIndex = try persistedConfiguration.getHighestSynchronizedIndex()
        self.pendingLocalCount = try getPendingLocalCount()

        try await connector.connect(databaseId: databaseId)
        updateStatus()

        // wait with this until the connector os connected
        self.highestRemoteIndex = await connector.getHighestRemoteIndex()
        
        print("📝 Database syncClient initialized; storage:", databaseFileUrl?.path ?? "in memory")
        print("Starting log from index \(self.highestSyncedLocalIndex)")
        print("Number of unsynchronized log entries: \(self.pendingLocalCount)")

        Task {
            for await syncStatus in connector.statusStream {
                self.connectorStatus = syncStatus
                self.updateStatus()
                statusContinuation.yield(self.status)
            }
        }
    }

    func updateStatus()
    {
        self.status = Status(
            connectorStatus: connectorStatus,
            currentSyncProgress: currentSyncProgress,
            pendingLocalChanges: pendingLocalCount,
            pendingRemoteChanges: pendingRemoteCount ?? 0,
            highestSyncedLocalIndex: highestSyncedLocalIndex,
            fatalError: fatalError
        )
        
        statusContinuation.yield(self.status)
    }

    func setHighestRemoteIndex(_ newValue: Int64)
    {
        self.highestRemoteIndex = newValue
    }
    
    func setDatabase(_ database: Database) async
    {
        self.database = database

        await connector.onHighestRemoteIndexIncrease { [weak self] updatedHighestRemoteIndex in
            guard let self else { return }
            await self.setHighestRemoteIndex(updatedHighestRemoteIndex)
            let highestLocalIndex = await self.highestSyncedLocalIndex
            guard updatedHighestRemoteIndex > highestLocalIndex else { return }
            await self.sync()
        }

        await connector.onDidConnectCallback { [weak self] in
            guard let self else { return }
            Task {
                await sync()
            }
        }

        Task {
            await self.sync()
        }
    }
    
    public func sync(force: Bool = false) async
    {
        await gate.run {
            isSyncing = true
            // repeatedly sync small batches to not block the insertion of new log entries
            
            let totalCount = self.pendingLocalCount + (self.pendingRemoteCount ?? 0)
            let progress = Progress(totalUnitCount: totalCount)
            self.currentSyncProgress = progress
            defer { self.currentSyncProgress = nil }
            
            guard totalCount > 0 || force else { return }
            
            while (self.pendingRemoteCount ?? 0) > 0 {
                guard await connector.isReady else {
                    retrySyncLater()
                    return
                }
                guard !isClosed else { return }
                await fetchAndUpdate()
                let remainingCount = self.pendingLocalCount + (self.pendingRemoteCount ?? 0)
                progress.completedUnitCount = Int64(totalCount - remainingCount)
            }
            
            while pendingLocalCount > 0 {
                guard await connector.isReady else {
                    retrySyncLater()
                    return
                }
                guard !isClosed else { return }
                await sendUnsynchronized()
                let remainingCount = self.pendingLocalCount + (self.pendingRemoteCount ?? 0)
                progress.completedUnitCount = Int64(totalCount - remainingCount)
            }
            
            if let newHighestRemoteIndex = await self.connector.getHighestRemoteIndex() {
                self.setHighestRemoteIndex(newHighestRemoteIndex)
            }
            
            if let pendingRemoteCount, pendingRemoteCount > 0 {
                Task {
                    await sync()
                }
            } else {
                isSyncing = false
            }
        }
    }
    
    private func retrySyncLater()
    {
        Task {
            try? await Task.sleep(for: .seconds(5))
        }
    }
    
    private func fetchAndUpdate() async
    {
        guard isSyncing else { return }

        guard let highestRemoteIndex, let pendingRemoteCount else {
            print("Failed to determine the highest remote index")
            return
        }

        print("Highest remote index \(highestRemoteIndex) (\(pendingRemoteCount) pending remote)")
        
        do {
            // TODO: publish progress information somewhere
            
            print("Fetching new entries, starting from index \(highestSyncedLocalIndex)")
            let newEntries = await connector.getEntries(from: highestSyncedLocalIndex, limit: 10_000)

            print("Received \(newEntries.count) entries to apply")

            guard newEntries.count > 0 else {
                // Connector returned 0 items; probably offline. Try again later.
                return
            }

            try logBatch(newEntries, source: .remote)

            try await markOutdatedFieldUpdatesAsApplied()

            let entriesToApply = try await getEntriesToApply()
            
            let groupedEntriesToApply = Dictionary(grouping: entriesToApply) { $0.transactionId }
            for (transactionId, entriesForTransaction) in groupedEntriesToApply.sorted(by: { ($0.value.first?.synchronizedIndex ?? 0) < ($1.value.first?.synchronizedIndex ?? 0) }) {
                let sortedEntriesForTransaction = entriesForTransaction.sorted(by: { ($0.synchronizedIndex ?? 0) < ($1.synchronizedIndex ?? 0) })
                try await database.processTransaction(entries: sortedEntriesForTransaction, transactionId: transactionId)
                try markEntriesAsAppliedLocally(transactionId: transactionId)
            }
            
            let highestSyncedIndexInReceivedEntries = newEntries.compactMap({ $0.synchronizedIndex }).reduce(highestSyncedLocalIndex) { max($0, $1) }

            try persistedConfiguration.setLastSuccessfulSync()
            try persistedConfiguration.setHighestSynchronizedIndex(highestSyncedIndexInReceivedEntries)
            
            self.highestSyncedLocalIndex = highestSyncedIndexInReceivedEntries
            print("Increased synced index to \(highestSyncedIndexInReceivedEntries)")
        } catch {
            // If we can't successfully read/write to the log, the database can't be used
            try? await database.close()
            fatalError = error
        }
    }
    
    private func sendUnsynchronized() async
    {
        guard isSyncing else { return }

        do {
            let entries = try await getEntriesToSend(limit: 10_000)
            print("Found \(entries.count) entries to send to sync")
            
            guard entries.count > 0 else { return }
            
            let updatedSynchronizationIndexes = await connector.sendEntries(entries: entries)
            if updatedSynchronizationIndexes.count != entries.count {
                print("Sent \(entries.count) to server but only received \(updatedSynchronizationIndexes.count) indexes")
            } else {
                print("Received \(updatedSynchronizationIndexes.count) indexes for sent entries")
            }
            
            try updateEntriesWithSynchronizationIndex(updatedSynchronizationIndexes)
            self.pendingLocalCount = try getPendingLocalCount()

            try persistedConfiguration.setLastSuccessfulSync()
        } catch {
            // If we can't successfully read/write to the log, the database can't be used
            try? await database.close()
            fatalError = error
        }
    }
    
    private static func initializeSchema(connectionHandle: OpaquePointer?) throws
    {
        let createTableSQL = """
        CREATE TABLE operation_log (
            id TEXT PRIMARY KEY NOT NULL,
            timestamp REAL NOT NULL,
            transaction_id TEXT NOT NULL,
            operation_type TEXT NOT NULL,
            table_name TEXT NOT NULL,
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
        
        try execute(createTableSQL, connectionHandle: connectionHandle)
        
        for indexSQL in createIndexSQL {
            try execute(indexSQL, connectionHandle: connectionHandle)
        }
        
        // Create configuration table
        let createConfigTableSQL = """
        CREATE TABLE configuration (
            key TEXT PRIMARY KEY NOT NULL,
            value ANY
        ) STRICT;
        """
        
        try execute(createConfigTableSQL, connectionHandle: connectionHandle)
    }
    
    private static func execute(_ sql: String, connectionHandle: OpaquePointer?) throws
    {
        let result = sqlite3_exec(connectionHandle, sql, nil, nil, nil)
        guard result == SQLiteStatus.ok else {
            let errmsg = String(cString: sqlite3_errmsg(connectionHandle))
            throw Error.failedToInitialize(errmsg)
        }
    }

    private func execute(_ sql: String) throws
    {
        try Self.execute(sql, connectionHandle: self.connectionHandle)
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
        sqlite3_bind_text(statement, 5, entry.tableName, -1, SQLITE_TRANSIENT)

        
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
            newValue.bind(to: statement, at: 8)
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
    public func logBatch(_ entries: [LogEntry], source: LogEntrySource) throws {
        try execute("BEGIN")
        
        do {
            for entry in entries {
                try log(entry, source: source)
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
                        guard fieldName != "id" else { continue } // The ID has to be set at row creation already; no point in updating it again
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
                        guard fieldName != "id" else { continue } // The ID has to be set at row creation already; no point in updating it again
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
        try logBatch(entries, source: .local)
        
        self.pendingLocalCount = try getPendingLocalCount()

        Task {
            await sync()
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
    
    private func getEntriesToSend(limit: Int64) async throws -> [LogEntry]
    {
        let sql = """
        SELECT 
            id, timestamp, transaction_id, operation_type,
            table_name, object_id, column_name, new_value, metadata,
            user, synchronized_index
        FROM operation_log
        WHERE transaction_id IN (
            SELECT DISTINCT transaction_id
            FROM (
                SELECT transaction_id
                FROM operation_log
                WHERE synchronized_index IS NULL
                ORDER BY synchronized_index ASC
                LIMIT ?
            )
        )
        ORDER BY timestamp ASC
        """
        
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(connectionHandle, sql, -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        
        guard let statement, prepareResult == SQLiteStatus.ok else {
            let errmsg = String(cString: sqlite3_errmsg(connectionHandle))
            throw Error.failedToLog(errmsg)
        }

        sqlite3_bind_int64(statement, 1, limit)

        var entries: [LogEntry] = []
        
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = UUID(uuidString: String(cString: sqlite3_column_text(statement, 0))),
                  let transactionId = UUID(uuidString: String(cString: sqlite3_column_text(statement, 2))),
                  let operationType = OperationType(rawValue: String(cString: sqlite3_column_text(statement, 3)))
            else {
                continue
            }
            
            let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(statement, 1))
            let tableName = String(cString: sqlite3_column_text(statement, 4))
            
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
                    throw Error.failedToLog("Unsupported column type")
                }
            } else {
                newValue = .null
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
        // Mark all such outdated values as "applied_locally = 1". These won't be applied to the local database. This works fine, even if they were part of a transaction, as all fields are nullable and foreign key checks are disabled while replaying (so setting a reference in a later transaction instead isn't an issue when replaying).
        
        let sql = """
        UPDATE operation_log
        SET applied_locally = 1
        WHERE id IN (
            SELECT id
            FROM (
                SELECT id,
                       ROW_NUMBER() OVER (
                           PARTITION BY table_name, object_id, column_name 
                           ORDER BY timestamp DESC, synchronized_index DESC
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
            let tableName = String(cString: sqlite3_column_text(statement, 4))
            
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
                newValue = .null
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
    
    // MARK: - Configuration Management
    
        
    /// Close the log database
    public func close() throws {
        guard !isClosed else { return }
        
        let result = sqlite3_close(connectionHandle)
        
        guard result == SQLiteStatus.ok else {
            throw Error.failedToClose(SQLiteStatus(result))
        }
        
        isClosed = true
        print("📝 Database syncClient closed")
    }
    
    isolated deinit
    {
        statusContinuation.finish()
        if !isClosed {
            sqlite3_close(connectionHandle)
        }
    }
}
