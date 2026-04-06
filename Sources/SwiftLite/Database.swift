import Foundation
import Observation
import SQLite3
import Synchronization

// Needs to be `Observable` to be used in SwiftUI's `Environment()`
public actor Database: Observable
{
    nonisolated public struct Status: Sendable, Equatable
    {
        public let localStatus: LocalDatabaseStatus
        public let syncStatus: SyncClient.Status
    }
    
    public enum LocalDatabaseStatus: Sendable, Equatable {
        case ok
        case fatalError(Swift.Error)
        
        public static func == (lhs: LocalDatabaseStatus, rhs: LocalDatabaseStatus) -> Bool {
            switch (lhs, rhs) {
            case (.ok, .ok):
                return true
            case (.fatalError(let lhsError), .fatalError(let rhsError)):
                return lhsError.localizedDescription == rhsError.localizedDescription
            default:
                return false
            }
        }
    }

    public enum StorageType: Sendable, Hashable {
        case file(URL)
        case inMemory
    }

    public enum SyncType {
        case disabled
        case enabled(using: any SyncConnector)
    }

    public enum CacheSize {
        case megabytes(Int)
        case pages(Int)
    }

    internal let connectionHandle: OpaquePointer
    internal var notificationProxies = [ActorNotificationProxy]()

    let gate = TransactionGate()

    public internal(set) var isClosed = false
    
    private let localStatus: Mutex<LocalDatabaseStatus> = .init(.ok)
    public nonisolated var status: LocalDatabaseStatus {
        localStatus.withLock { $0 }
    }
    
    public nonisolated let statusUpdates = AsyncStreams<Status>()

    // Logging for distributed sync
    public private(set) var syncClient: SyncClient?
    internal var currentTransactionId: UUID?
    internal var pendingSchemaChanges: [SyncClient.SchemaChange] = []
    
    public let isFirstOpening: Bool
    public nonisolated let hasSync: Bool
    
    public init(storage: StorageType, sync: SyncType = .disabled, cacheSizeLimit: CacheSize? = nil) async throws
    {
        var flags = [SQLITE_OPEN_READWRITE, SQLITE_OPEN_CREATE, SQLITE_OPEN_FULLMUTEX]
        var databaseFileUrl: URL?

        switch storage {
        case .file(let url):
            guard url.isFileURL else { throw Error.notAFileUrl(url) }
            if url.exists {
                print("Opening database at \(url.filePath)")
                isFirstOpening = false
            } else {
                print("Creating database at \(url.filePath)")
                try url.createParentDirectoryIfNotExists()
                isFirstOpening = true
            }
            databaseFileUrl = url
        case .inMemory:
            isFirstOpening = true
            flags.append(SQLITE_OPEN_MEMORY)
            print("Opening database in memory")
        }
        
        switch sync {
        case .disabled:
            hasSync = false
        case .enabled(let syncConnector):
            self.syncClient = try await SyncClient(connector: syncConnector, databaseStorage: storage)
            hasSync = true
        }
        
        let databaseFilePath = databaseFileUrl?.filePath
        
        var pointer: OpaquePointer?
        let openStatus = sqlite3_open_v2(databaseFilePath, &pointer, flags.reduce(0, |), nil)
        
        guard let pointer, openStatus == SQLiteStatus.ok else {
            throw Error.failedToOpen(SQLiteStatus(openStatus))
        }
        
        do {
            if let cacheSizeLimit {
                let limit = switch cacheSizeLimit {
                case .megabytes(let value): -value * 256
                case .pages(let value): value
                }
                try Self.setPragma(name: "cache_size", value: String(limit), connectionHandle: pointer)
            }
            
            // As per https://sqlite.org/foreignkeys.html: "Foreign key constraints are disabled by default (for backwards compatibility), so must be enabled separately for each database connection".
            try Self.setPragma(name: "foreign_keys", value: "ON", connectionHandle: pointer)
        } catch {
            sqlite3_close_v2(pointer)
            throw error
        }

        self.connectionHandle = pointer
        
        if let syncClient {
            Task {
                for await syncStatus in syncClient.statusStream {
                    let localStatus = self.localStatus.withLock { $0 }
                    let updatedStatus = Status(localStatus: localStatus, syncStatus: syncStatus)
                    statusUpdates.yield(updatedStatus)
                }
            }
        }

        await syncClient?.setDatabase(self)
    }
    
    func setPragma(name: String, value: String) throws
    {
        try Self.setPragma(name: name, value: value, connectionHandle: self.connectionHandle)
    }

    static func setPragma(name: String, value: String, connectionHandle: OpaquePointer) throws
    {
        let statementText = "PRAGMA \(name) = \(value)"
        let result = sqlite3_exec(connectionHandle, statementText, nil, nil, nil)
        guard result == SQLiteStatus.ok else {
            let errmsg = String(cString: sqlite3_errmsg(connectionHandle))
            print("🔴 Error while executing query: \(errmsg)")
            throw Error.queryFailed(sqlStatement: .init(text: statementText), status: SQLiteStatus(result), errorMessage: errmsg)
        }
    }
    
    public func backup(to url: URL) async throws
    {
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("export.db")

        print("SQLite version: \(String(cString: sqlite3_libversion()))")

        // TODO: More error handling
        var pDest: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        sqlite3_open_v2(tempPath.path(percentEncoded: false), &pDest, flags, nil)
        let backup = sqlite3_backup_init(pDest, "main", self.connectionHandle, "main")

        if backup == nil {
            print("backup_init failed: \(String(cString: sqlite3_errmsg(pDest)))")
        } else {
            let stepResult = sqlite3_backup_step(backup, -1)
            let remaining = sqlite3_backup_remaining(backup)
            let pagecount = sqlite3_backup_pagecount(backup)
            let finishResult = sqlite3_backup_finish(backup)
            
            print("step result: \(stepResult)")      // expect SQLITE_DONE (101)
            print("remaining: \(remaining)")
            print("pagecount: \(pagecount)")
            print("finish result: \(finishResult)")  // expect SQLITE_OK (0)
        }
        sqlite3_close(pDest)

        _ = tempPath.startAccessingSecurityScopedResource()
        defer { tempPath.stopAccessingSecurityScopedResource() }

        try FileManager.default.moveItem(
            atPath: tempPath.path(percentEncoded: false),
            toPath: url.path(percentEncoded: false)
        )
    }

    public func register<each T: Model>(models: repeat (each T).Type) async throws
    {
        // TODO: Store registered models and run check when querying if the model in question was registered?
        
        let existingTables = try getUserDefinedTables()
        var tablesWithoutMatchingModels = Set(existingTables)
        var requiredTables = Set<RequiredSchema.Table>()

        for model in repeat each models {
            requiredTables.insert(model.Schema.table)
            for relatedSchema in model.Schema.related {
                requiredTables.insert(relatedSchema.table)
            }
        }
        
        try await gate.run {
            let transactionId = UUID.v7()
            currentTransactionId = transactionId
            pendingSchemaChanges = []
            
            print("▶️ BEGINNING SCHEMA UPDATE TRANSACTION")
            try self.run("BEGIN")
            do {
                // Note: The order in which the tables are created is irrelevant while in a transaction, regardless if they reference each other.
                for table in requiredTables {
                    print("Checking table \(table.name)...")
                    let existingTableForModel = existingTables.first { $0.name == table.name }
                    if let existingTableForModel {
                        print("exists; comparing...")
                        tablesWithoutMatchingModels.remove(existingTableForModel)
                        // compare schema
                        try await updateTableIfNecessary(existingTable: existingTableForModel, table: table)
                    } else {
                        print("doesn't exist; creating...")
                        try await createTable(table)
                    }

                }
                try self.run("COMMIT")
                print("✅ COMMITTED SCHEMA UPDATE TRANSACTION")
                
                // Transaction succeeded - log all schema changes in a batch
                if !pendingSchemaChanges.isEmpty {
                    try? await syncClient?.logTransactionBatch(
                        transactionId: transactionId,
                        schemaChanges: pendingSchemaChanges,
                        dataChanges: []
                    )
                }
            } catch {
                try? self.run("ROLLBACK")
                print("✴️ ROLLED BACK SCHEMA UPDATE TRANSACTION")
                // Failed transaction - don't log, just clean up
                currentTransactionId = nil
                pendingSchemaChanges = []
                throw error
            }
            
            currentTransactionId = nil
            pendingSchemaChanges = []
        }
        
        for tablesWithoutMatchingModel in tablesWithoutMatchingModels {
            print("Ignoring user-defined table that doesn't map to any model: \(tablesWithoutMatchingModel.name)")
        }
    }
    
    public func run(_ sqlStatement: SQLStatement) throws
    {
        if let values = sqlStatement.values {
            guard values.isEmpty else { throw Error.unexpectedStatementValuesForRun }
        }
        try run(sqlStatement.text)
    }

    public func run(_ statementText: String) throws
    {
        let result = sqlite3_exec(self.connectionHandle, statementText, nil, nil, nil)
        guard result == SQLiteStatus.ok else {
            let errmsg = String(cString: sqlite3_errmsg(self.connectionHandle))
            print("🔴 Error while executing query: \(errmsg)")
            throw Error.queryFailed(sqlStatement: .init(text: statementText), status: SQLiteStatus(result), errorMessage: errmsg)
        }
    }
    
    @discardableResult
    public func execute(_ sqlStatement: SQLStatement) throws -> [Row]
    {
        var statement: OpaquePointer?
                
        #if DEBUG
        print("SQL:", sqlStatement.text, sqlStatement.values?.map { $0.debugDescription } ?? [])
        #endif
        
        let result = sqlite3_prepare_v2(self.connectionHandle, sqlStatement.text, -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        guard let statement else { throw Error.failedToFindStatement }
        
        guard result == SQLiteStatus.ok else  {
            let errmsg = String(cString: sqlite3_errmsg(self.connectionHandle))
            print("🔴 Error while executing query: \(errmsg)")
            throw Error.queryFailed(sqlStatement: sqlStatement, status: SQLiteStatus(result), errorMessage: errmsg)
        }
        
        if let valuesToBind = sqlStatement.values {
            var index: CInt = 1
            for value in valuesToBind {
                defer { index += 1 }
                value.bind(to: statement, at: index)
            }
        }
        
        var results = [Row]()
        
        // TODO: Log/handle errors returned from `sqlite3_step()`. Also consider retrying for `SQLITE_BUSY` and `SQLITE_LOCKED` (after a delay).
        
        step: while true {
            let stepResult = sqlite3_step(statement)
            switch stepResult {
//            case SQLITE_OK: // Successful result
//            case SQLITE_ERROR: // Generic error
//            case SQLITE_INTERNAL: // Internal logic error in SQLite
//            case SQLITE_PERM: // Access permission denied
//            case SQLITE_ABORT: // Callback routine requested an abort
//            case SQLITE_BUSY: // The database file is locked
//            case SQLITE_LOCKED: // A table in the database is locked
//            case SQLITE_NOMEM: // A malloc() failed
//            case SQLITE_READONLY: // Attempt to write a readonly database
//            case SQLITE_INTERRUPT: // Operation terminated by sqlite3_interrupt()
//            case SQLITE_IOERR: // Some kind of disk I/O error occurred
//            case SQLITE_CORRUPT: // The database disk image is malformed
//            case SQLITE_NOTFOUND: // Unknown opcode in sqlite3_file_control()
//            case SQLITE_FULL: // Insertion failed because database is full
//            case SQLITE_CANTOPEN: // Unable to open the database file
//            case SQLITE_PROTOCOL: // Database lock protocol error
//            case SQLITE_EMPTY: // Internal use only
//            case SQLITE_SCHEMA: // The database schema changed
//            case SQLITE_TOOBIG: // String or BLOB exceeds size limit
//            case SQLITE_CONSTRAINT: // Abort due to constraint violation
//            case SQLITE_MISMATCH: // Data type mismatch
//            case SQLITE_MISUSE: // Library used incorrectly
//            case SQLITE_NOLFS: // Uses OS features not supported on host
//            case SQLITE_AUTH: // Authorization denied
//            case SQLITE_FORMAT: // Not used
//            case SQLITE_RANGE: // 2nd parameter to sqlite3_bind out of range
//            case SQLITE_NOTADB: // File opened that is not a database file
//            case SQLITE_NOTICE: // Notifications from sqlite3_log()
//            case SQLITE_WARNING: // Warnings from sqlite3_log()
            case SQLITE_ROW: // sqlite3_step() has another row ready
                let row = Database.Row(db: self, statement: statement)
                results.append(row)
            case SQLITE_DONE: // sqlite3_step() has finished executing
                break step
            default:
                throw Error.sqliteError(code: stepResult)
            }
        }
        
        return results
    }
    
    internal func pragma<T: InitializableFromResultRow>(_ name: String, expecting: T.Type = T.self) throws -> [T]
    {
        let pragmaConfiguration = SQLStatementPreset.Pragma(name: name)
        let rows = try execute(pragmaConfiguration.sqlStatement)
        return try rows.map { try T(db: self, row: $0) }
    }

    private nonisolated(nonsending) func objects<T: Fetchable>(type: T.Type = T.self, sqlStatement: SQLStatement) async throws -> [T]
    {
        try await withReadTransaction {
            let rows = try await self.execute(sqlStatement)
            var objects = [T]()
            objects.reserveCapacity(rows.count)
            
            let associatedData = try ReadAssociatedData.getCurrent()

            for row in rows {
                guard let id: UUID = try? row.get("id") else {
                    print("🔴 Failed to initialize \(T.self): ID could not be found", row)
                    continue
                }
                        
                if let existingObject = associatedData.getCached(T.self, id: id) {
                    objects.append(existingObject)
                    continue
                }
                
                try associatedData.checkForRecursion(id)
                
                do {
                    let object = try await T(db: self, row: row)
                    objects.append(object)
                    associatedData.addCached(T.self, id: id, object: object)
                } catch {
                    // TODO: Make `Database` configurable if this should be an error (and not return any items) instead of skipping the ones that can't be initialized
                    print("🔴 Failed to initialize \(T.self) with ID \(id): \(error.localizedDescription)", row)
                }
            }

            return objects
        }
    }

    public nonisolated(nonsending) func count<T: Fetchable>(_ type: T.Type, where filter: SQLWhereClauseConvertible? = nil) async throws -> Int
    {
        let countColumn = "COUNT(*)"
        var preset = SQLStatementPreset.Select(table: T.Model.Schema.table.name, columnExpression: countColumn)
        if let filter {
            preset = preset.withConditions(try filter.toSQL())
        }
        let rows = try await execute(preset.sqlStatement)
        guard let count = try rows.first?.get(countColumn, as: Int.self) else {
            throw Error.failedToFindResultValue
        }
        return count
    }

    public nonisolated(nonsending) func find<T: Fetchable>(_ type: T.Type, where filter: SQLWhereClauseConvertible, sortBy: SQLSortClauseConvertible? = nil) async throws -> [T]
    {
        let orderByClause = sortBy?.toSQL()
        let preset = T.Model.Schema.table.defaultSelectStatement.withConditions(try filter.toSQL(), orderBy: orderByClause?.text)
        return try await objects(type: T.self, sqlStatement: preset.sqlStatement)
    }

    public nonisolated(nonsending) func find<T: Fetchable>(_ type: T.Type, condition: any SQLExpression) async throws -> [T]
    {
        let preset = T.Model.Schema.table.defaultSelectStatement.withConditions(condition)
        return try await objects(type: T.self, sqlStatement: preset.sqlStatement)
    }

    public nonisolated(nonsending) func get<T: Fetchable>(_ type: T.Type) async throws -> [T]
    {
        let preset = T.Model.Schema.table.defaultSelectStatement
        return try await objects(type: T.self, sqlStatement: preset.sqlStatement)
    }
    
    public nonisolated(nonsending) func get<T: Fetchable>(_ type: T.Type, sortBy: SQLSortClauseConvertible? = nil) async throws -> [T]
    {
        var preset = T.Model.Schema.table.defaultSelectStatement
        if let sortClause = sortBy?.toSQL() {
            preset = preset.withOrderBy(sortClause.text)
        }
        return try await objects(type: T.self, sqlStatement: preset.sqlStatement)
    }

    public nonisolated(nonsending) func get<T: Fetchable>(_ type: T.Type, id: UUID) async throws -> T?
    {
        let preset = T.Model.Schema.table.defaultSelectStatement.withCondition(.byId(id), limit: 1)
        return try await objects(type: T.self, sqlStatement: preset.sqlStatement).first
    }

    public nonisolated(nonsending) func get<T: Fetchable, I: Fetchable>(_ type: T.Type = T.self, from other: I) async throws -> T? where T.Model == I.Model
    {
        let preset = T.Model.Schema.table.defaultSelectStatement.withCondition(.byId(other.id), limit: 1)
        return try await objects(type: T.self, sqlStatement: preset.sqlStatement).first
    }

    public nonisolated(nonsending) func resolve<T: Fetchable>(_ reference: DirectRelationReference<T.Model>) async throws -> T
    {
        let id = reference.id
        let result = try await get(T.self, id: id)
        guard let result else { throw Database.Error.failedToFindReferencedObject(table: T.Model.Schema.table.name, id: id) }
        return result
    }
    
    public nonisolated(nonsending) func delete<T: Fetchable>(_ type: T.Type, id: UUID) async throws
    {
        guard let object = try await get(T.Model.self, id: id) else { return }
        try await object.delete()
    }

    nonisolated(nonsending) func withReadTransaction<T: Fetchable>(_ body: @escaping () async throws -> sending [T]) async throws -> [T]
    {
        guard ReadAssociatedData.current == nil else {
            return try await body()
        }
        
        var results = [T]()
        
        try await gate.run {
            print("▶️ BEGINNING READ TRANSACTION")
            let associatedData = ReadAssociatedData(db: self)
            
            try await ReadAssociatedData.$current.withValue(associatedData) {
                try await self.run("BEGIN")
                do {
                    results = try await body()
                    try await self.run("COMMIT")
                    ReadAssociatedData.current?.printStatistics()
                    print("✅ COMMITTED READ TRANSACTION")
                } catch {
                    try? await self.run("ROLLBACK")
                    print("✴️ ROLLED BACK READ TRANSACTION")
                    print("Error while executing read transaction:", error.localizedDescription)
                    throw error
                }
            }
        }
        
        // Start autoupdating here, because at this point, the Model objects should be back on actor they'll live in (even if that's not where they were created).

        let isMainActor = #isolation === MainActor.shared
        

        if isMainActor, let autoupdatingModels = results as? [AutoupdatingModel] {
            nonisolated(unsafe) let unsafeModels = autoupdatingModels
            await MainActor.run {
                unsafeModels.forEach { $0._beginAutoupdating() }
            }
        }
        
        return results
    }

    public func save(changeset: FrozenChangeset) async throws
    {
        try await gate.run {
            let transactionId = UUID.v7()
            currentTransactionId = transactionId
            
            print("▶️ BEGINNING WRITE TRANSACTION")
            var transactionCompletedSuccessfully = false
            try self.run("BEGIN")
            do {
                try self.setPragma(name: "defer_foreign_keys", value: "ON") // to wait with enforcement until `COMMIT`

                for object in changeset.changes {
                    let byObjectId = SQLWhereClause.byId(object.objectId)
                    
                    switch object.status {
                    case .created:
                        guard let updatedFields = object.updatedFields else { continue }
                        let preset = SQLStatementPreset.Insert(table: object.table, updatedFields: updatedFields)
                        try self.execute(preset.sqlStatement)
                    case .deleted:
                        let preset = SQLStatementPreset.Delete(table: object.table, conditions: byObjectId)
                        try self.execute(preset.sqlStatement)
                    case .updated:
                        guard let updatedFields = object.updatedFields else { continue }
                        let preset = SQLStatementPreset.Update(table: object.table, updatedFields: updatedFields, condition: byObjectId)
                        try self.execute(preset.sqlStatement)
                    }
                }
                try self.run("COMMIT")
                print("✅ COMMITTED WRITE TRANSACTION")
                transactionCompletedSuccessfully = true
                
                // Transaction succeeded - log all data changes in a batch
                try? await syncClient?.logTransactionBatch(
                    transactionId: transactionId,
                    schemaChanges: [],
                    dataChanges: changeset.changes
                )
            } catch {
                try? self.run("ROLLBACK")
                print("✴️ ROLLED BACK WRITE TRANSACTION")
                // Failed transaction - don't log anything
                currentTransactionId = nil
                throw error
            }

            currentTransactionId = nil
            
            if transactionCompletedSuccessfully {
                Task {
                    for proxy in self.notificationProxies {
                        proxy.onChange(changeset: changeset)
                    }
                }
            }
        }
    }



    public func close() throws
    {
        guard !isClosed else { return }
        
        let result = sqlite3_close(self.connectionHandle)

        Task {
            // Close the syncClient first
            try? await syncClient?.close()
        }

        guard result == SQLiteStatus.ok else {
            throw Error.failedToClose(SQLiteStatus(result))
        }
        
        isClosed = true
    }
    
    public func registerNotificationProxy(_ proxy: ActorNotificationProxy)
    {
        notificationProxies.append(proxy)
    }
    
        
    isolated deinit
    {
        statusUpdates.finish()

        if !isClosed {
            sqlite3_close(self.connectionHandle)
        }
        
        let syncClient = self.syncClient
        Task {
            try? await syncClient?.close()
        }
    }
}

extension Database: Equatable
{
    public static func == (lhs: Database, rhs: Database) -> Bool {
        ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
    }
}
