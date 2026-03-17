import Foundation
import Observation
import SQLite3

// Needs to be `Observable` to be used in SwiftUI's `Environment()`
public actor Database: Observable
{
    public enum StorageType {
        case file(URL)
        case inMemory
    }
    
    public enum CacheSize {
        case megabytes(Int)
        case pages(Int)
    }

    enum Error: Swift.Error, CustomStringConvertible, Sendable, Equatable {
        case queryFailed(sqlStatement: SQLStatement, status: SQLiteStatus, errorMessage: String)
        case failedToOpen(SQLiteStatus)
        case failedToClose(SQLiteStatus)
        case failedToFindReferencedObject(table: String, id: UUID)
        case notAFileUrl(URL)
        case failedToFindStatement
        case sqliteError(code: Int32)
        case failedToFindResultValue
        case failedToFindReadTransaction
        case failedToMigrateSchema

        var description: String {
            return switch self {
            case .queryFailed(let configuration, let status, let errorMessage):
                "Query `\(configuration.text)` failed: \(status.description) (\(errorMessage))"
            case .failedToOpen(let status):
                "Failed to open database: \(status.description))"
            case .failedToClose(let status):
                "Failed to close database: \(status.description)"
            case .notAFileUrl(let url):
                "URL \(url) is not a file URL"
            case .failedToFindReferencedObject(table: let table, id: let id):
                "Failed to find referenced object of type \(table) with id \(id)"
            case .failedToFindStatement:
                "Failed to find the SQLite statement pointer"
            case .sqliteError(code: let code):
                "SQLite error code: \(code)"
            case .failedToFindResultValue:
                "Failed to find result value"
            case .failedToFindReadTransaction:
                "Failed to find a read transaction"
            case .failedToMigrateSchema:
                "Failed to migrate schema"
            }
        }
    }
    
    internal let connectionHandle: OpaquePointer
    internal var notificationProxies = [ActorNotificationProxy]()

    let gate = TransactionGate()

    public internal(set) var isClosed = false
    
    // Logging for distributed sync
    private var logger: DatabaseLogger?
    private var currentTransactionId: UUID?

    public init(storage: StorageType, cacheSizeLimit: CacheSize? = nil, enableLogging: Bool = true) async throws
    {
        var pointer: OpaquePointer?
        var flags = [SQLITE_OPEN_READWRITE, SQLITE_OPEN_CREATE, SQLITE_OPEN_FULLMUTEX] // see https://sqlite.org/c3ref/open.html
        var filename: String?
        var logFileURL: URL?
        
        if case .file(let url) = storage {
            guard url.isFileURL else {
                throw Error.notAFileUrl(url)
            }
            let filenameFromUrl = url.absoluteString
            filename = filenameFromUrl
            print("Opening database at \(filenameFromUrl)")
            
            // Create log file URL (same directory, with .log.sqlite extension)
            if enableLogging {
                let logFileName = url.deletingPathExtension().lastPathComponent + ".log.sqlite"
                logFileURL = url.deletingLastPathComponent().appendingPathComponent(logFileName)
            }
        } else if case .inMemory = storage {
            flags.append(SQLITE_OPEN_MEMORY)
            print("Opening database in memory")
            // In-memory databases don't get logging
        }
        
        let openStatus = sqlite3_open_v2(filename, &pointer, flags.reduce(0, |), nil)
        
        guard let pointer, openStatus == SQLiteStatus.ok else {
            throw Error.failedToOpen(SQLiteStatus(openStatus))
        }
        
        do {
            if let cacheSizeLimit {
                let limit = switch cacheSizeLimit {
                case .megabytes(let value): -value * 1024
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
        
        // Initialize logger if enabled and we have a file URL
        if enableLogging, let logFileURL {
            do {
                self.logger = try await DatabaseLogger(logFileURL: logFileURL)
            } catch {
                print("⚠️ Failed to initialize database logger: \(error)")
                // Continue without logging - don't fail database initialization
            }
        }
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

    public func register<each T: Model>(models: repeat (each T).Type) async throws
    {
        // TODO:
        // 1. Build model graph (to find referenced model types and dependencies)
        // 2. Check if table(s) exists already
        //  if yes:
        //      1. Compare schema (names and types should match; not sure about "STRICT" and "WITHOUT ROWID"; column order is irrelevant)
        //          if schema matches, continue
        //          if schema doesn't match, execute migration to new schema (traversing the graph upwards)
        //  if no:
        //      1. create table (traversing the graph upwards)
        
        // TODO: Store registered models; run check when querying if the model in question was registered
        
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
            let transactionId = UUID()
            currentTransactionId = transactionId
            
            print("▶️ BEGINNING SCHEMA UPDATE TRANSACTION")
            try? await logger?.logTransactionBegin(transactionId: transactionId, type: "schema_update")
            
            try self.run("BEGIN")
            do {
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
                try? await logger?.logTransactionCommit(transactionId: transactionId)
                print("✅ COMMITTED SCHEMA UPDATE TRANSACTION")
            } catch {
                try? self.run("ROLLBACK")
                try? await logger?.logTransactionRollback(transactionId: transactionId)
                print("✴️ ROLLED BACK SCHEMA UPDATE TRANSACTION")
                throw error
            }
            
            currentTransactionId = nil
        }
        
        for tablesWithoutMatchingModel in tablesWithoutMatchingModels {
            print("Ignoring user-defined table that doesn't map to any model: \(tablesWithoutMatchingModel.name)")
        }
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
                switch value {
                case .string(let string):
                    sqlite3_bind_text(statement, index, string, -1, SQLITE_TRANSIENT)
                case .int(let integer):
                    sqlite3_bind_int64(statement, index, integer)
                case .double(let value):
                    sqlite3_bind_double(statement, index, value)
                case .data(let data):
                    _ = data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
                        sqlite3_bind_blob(statement, 1, bytes.baseAddress, Int32(data.count), SQLITE_TRANSIENT)
                    }
                case .null:
                    sqlite3_bind_null(statement, index)
                }
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
    
    private func pragma<T: InitializableFromResultRow>(_ name: String, expecting: T.Type = T.self) throws -> [T]
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
                let id: UUID = try row.get("id")
                if let existingObject = associatedData.getCached(T.self, id: id) {
                    objects.append(existingObject)
                } else {
                    let object = try await T(db: self, row: row)
                    objects.append(object)
                    associatedData.addCached(T.self, id: id, object: object)
                }
            }

            return objects
        }
    }

    public nonisolated(nonsending) func count<T: Fetchable>(_ type: T.Type, where queryBuilder: (Query<T>.Proxy) -> Query<T>.Proxy.Predicate) async throws -> Int
    {
        let query = Query<T>(queryBuilder)
        return try await count(T.self, query: query)
    }

    public nonisolated(nonsending) func count<T: Fetchable>(_ type: T.Type, query: Query<T>? = nil) async throws -> Int
    {
        let columnName = "COUNT(*)"
        var preset = SQLStatementPreset.Select(table: T.Model.Schema.table.name, columns: [columnName])
        if let query {
            preset = preset.withConditions(query)
        }
        let rows = try await execute(preset.sqlStatement)
        guard let count = try rows.first?.get(columnName, as: Int.self) else {
            throw Error.failedToFindResultValue
        }
        return count
    }

    public nonisolated(nonsending) func find<T: Fetchable>(_ type: T.Type, where queryBuilder: (Query<T>.Proxy) -> Query<T>.Proxy.Predicate) async throws -> [T]
    {
        let query = Query<T>(queryBuilder)
        return try await find(T.self, query: query) 
    }

    public nonisolated(nonsending) func find<T: Fetchable>(_ type: T.Type, query: Query<T>) async throws -> [T]
    {
        let preset = T.Model.Schema.table.defaultSelectStatement.withConditions(query)
        return try await objects(type: T.self, sqlStatement: preset.sqlStatement)
    }

    public nonisolated(nonsending) func find<T: Fetchable>(_ type: T.Type, condition: SQLCondition) async throws -> [T]
    {
        let preset = T.Model.Schema.table.defaultSelectStatement.withConditions(condition)
        return try await objects(type: T.self, sqlStatement: preset.sqlStatement)
    }

    public nonisolated(nonsending) func get<T: Fetchable>(_ type: T.Type) async throws -> [T]
    {
        let preset = T.Model.Schema.table.defaultSelectStatement
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
            let transactionId = UUID()
            await self.setCurrentTransactionId(transactionId)
            
            print("▶️ BEGINNING READ TRANSACTION")
            try? await logger?.logTransactionBegin(transactionId: transactionId, type: "read")
            
            let associatedData = ReadAssociatedData(db: self)
            
            try await ReadAssociatedData.$current.withValue(associatedData) {
                try await self.run("BEGIN")
                do {
                    results = try await body()
                    try await self.run("COMMIT")
                    try? await logger?.logTransactionCommit(transactionId: transactionId)
                    print("✅ COMMITTED READ TRANSACTION")
                } catch {
                    try? await self.run("ROLLBACK")
                    try? await logger?.logTransactionRollback(transactionId: transactionId)
                    print("✴️ ROLLED BACK READ TRANSACTION")
                    throw error
                }
            }
            
            await self.setCurrentTransactionId(nil)
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
    
    private func setCurrentTransactionId(_ id: UUID?) {
        currentTransactionId = id
    }

    public func save(changeset: FrozenChangeset) async throws
    {
        try await gate.run {
            let transactionId = UUID()
            currentTransactionId = transactionId
            
            print("▶️ BEGINNING WRITE TRANSACTION")
            try? await logger?.logTransactionBegin(transactionId: transactionId, type: "write")
            
            var transactionCompletedSuccessfully = false
            try self.run("BEGIN")
            do {
                try self.setPragma(name: "defer_foreign_keys", value: "ON") // to wait with enforcement until `COMMIT`

                // TODO: Log changes and mark them for synchronization

                for object in changeset.changes {
                    let byObjectId = SQLCondition(field: "id", value: object.objectId.convertToSQLValue())
                    
                    switch object.status {
                    case .created:
                        guard let updatedFields = object.updatedFields else { continue }
                        let preset = SQLStatementPreset.Insert(table: object.table, updatedFields: updatedFields)
                        try self.execute(preset.sqlStatement)
                        
                        // Log the creation
                        try? await logger?.logDataChange(transactionId: transactionId, change: object)
                        
                    case .deleted:
                        let preset = SQLStatementPreset.Delete(table: object.table, conditions: [byObjectId])
                        try self.execute(preset.sqlStatement)
                        
                        // Log the deletion
                        try? await logger?.logDataChange(transactionId: transactionId, change: object)
                        
                    case .updated:
                        guard let updatedFields = object.updatedFields else { continue }
                        let preset = SQLStatementPreset.Update(table: object.table, updatedFields: updatedFields, condition: byObjectId)
                        try self.execute(preset.sqlStatement)
                        
                        // Log the update
                        try? await logger?.logDataChange(transactionId: transactionId, change: object)
                    }
                }
                try self.run("COMMIT")
                try? await logger?.logTransactionCommit(transactionId: transactionId)
                print("✅ COMMITTED WRITE TRANSACTION")
                transactionCompletedSuccessfully = true
            } catch {
                try? self.run("ROLLBACK")
                try? await logger?.logTransactionRollback(transactionId: transactionId)
                print("✴️ ROLLED BACK WRITE TRANSACTION")
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

    func updateTableIfNecessary(existingTable: ExistingSchema.Table, table: RequiredSchema.Table) async throws
    {
        // Get existing schema details
        let existingColumns = try getColumns(tableName: table.name)
        let existingIndexes = try getIndexes(tableName: table.name)
        
        // Compare table properties
        let needsRecreation = existingTable.isStrict != true || existingTable.isWithoutRowId != true
        
        // Compare columns
        var columnsToAdd = [RequiredSchema.Column]()
        var columnTypeChanged = false
        
        // Build a map of existing columns for quick lookup
        let existingColumnMap = Dictionary(uniqueKeysWithValues: existingColumns.map { ($0.name, $0) })
        let requiredColumnMap = Dictionary(uniqueKeysWithValues: table.columns.map { ($0.name, $0) })
        
        // Check for columns that need to be added or have changed types
        for requiredColumn in table.columns {
            if let existingColumn = existingColumnMap[requiredColumn.name] {
                // Column exists, check if type matches
                if existingColumn.storageClass != requiredColumn.storageClass {
                    print("⚠️ Column '\(requiredColumn.name)' type changed from \(existingColumn.storageClass.rawValue) to \(requiredColumn.storageClass.rawValue)")
                    columnTypeChanged = true
                }
            } else {
                // Column doesn't exist, needs to be added
                columnsToAdd.append(requiredColumn)
            }
        }
        
        // Compare indexes
        var indexesToAdd = [RequiredSchema.Index]()
        var indexesToRemove = [ExistingSchema.Index]()
        
        // Filter out system-generated indexes (like primary key indexes)
        let userCreatedIndexes = existingIndexes.filter { $0.origin == .createIndex }
        
        let existingIndexMap = Dictionary(uniqueKeysWithValues: userCreatedIndexes.map { ($0.name, $0) })
        let requiredIndexMap = Dictionary(uniqueKeysWithValues: table.indexes.map { ($0.name, $0) })
        
        for requiredIndex in table.indexes {
            if let existingIndex = existingIndexMap[requiredIndex.name] {
                // Index exists, check if it matches
                let columnsMatch = existingIndex.columns == requiredIndex.columns
                let uniquenessMatches = existingIndex.isUnique == requiredIndex.isUnique
                
                if !columnsMatch || !uniquenessMatches {
                    // Index needs to be recreated
                    indexesToRemove.append(existingIndex)
                    indexesToAdd.append(requiredIndex)
                }
            } else {
                // Index doesn't exist
                indexesToAdd.append(requiredIndex)
            }
        }
        
        // Check for indexes to remove
        for existingIndex in userCreatedIndexes {
            if requiredIndexMap[existingIndex.name] == nil {
                indexesToRemove.append(existingIndex)
            }
        }
        
        // Decide on migration strategy
        if needsRecreation || columnTypeChanged {
            // Would need to recreate the table, which is not supported
            print("⛔️ Schema migration failed; Table '\(table.name)' requires structural changes")
            throw Error.failedToMigrateSchema
        } else {
            // Can use simpler ALTER TABLE operations
            
            // Add new columns
            for column in columnsToAdd {
                print("➕ Adding column '\(column.name)' to table '\(table.name)'")
                let alterStatement = "ALTER TABLE \"\(table.name)\" ADD COLUMN \"\(column.name)\" \(column.storageClass.rawValue.uppercased())"
                try run(alterStatement)
                
                // Log column addition
                if let transactionId = currentTransactionId {
                    try? await logger?.logSchemaChange(
                        transactionId: transactionId,
                        operationType: .columnAdded,
                        tableName: table.name,
                        columnName: column.name,
                        metadata: ["storageClass": column.storageClass.rawValue]
                    )
                }
            }
            
            // Update indexes
            for index in indexesToRemove {
                print("🗑️ Dropping index '\(index.name)'")
                try run("DROP INDEX \"\(index.name)\"")
                
                // Log index removal
                if let transactionId = currentTransactionId {
                    try? await logger?.logSchemaChange(
                        transactionId: transactionId,
                        operationType: .indexDropped,
                        tableName: table.name,
                        metadata: ["indexName": index.name]
                    )
                }
            }
            
            for index in indexesToAdd {
                print("➕ Creating index '\(index.name)'")
                let createIndexStatement = "CREATE \(index.isUnique ? "UNIQUE " : "")INDEX \"\(index.name)\" ON \"\(table.name)\"(\(index.columns.joined(separator: ", ")))"
                try run(createIndexStatement)
                
                // Log index creation
                if let transactionId = currentTransactionId {
                    try? await logger?.logSchemaChange(
                        transactionId: transactionId,
                        operationType: .indexCreated,
                        tableName: table.name,
                        metadata: [
                            "indexName": index.name,
                            "isUnique": index.isUnique,
                            "columns": index.columns
                        ]
                    )
                }
            }
        }
    }
    
    func createTable(_ table: RequiredSchema.Table) async throws
    {
        let createTableStatement = createTableStatement(for: table)
        let createIndexStatements = createIndexStatements(for: table)
        print(createTableStatement)
        try self.run(createTableStatement)
        
        // Log table creation
        if let transactionId = currentTransactionId {
            let columnInfo = table.columns.map { ["name": $0.name, "storageClass": $0.storageClass.rawValue] }
            let foreignKeyInfo = table.foreignKeys.map { [
                "column": $0.column,
                "referencedTable": $0.referencedTable,
                "referencedColumn": $0.referencedColumn
            ] }
            
            try? await logger?.logSchemaChange(
                transactionId: transactionId,
                operationType: .tableCreated,
                tableName: table.name,
                metadata: [
                    "columns": columnInfo,
                    "foreignKeys": foreignKeyInfo
                ]
            )
            
            // Log foreign key additions
            for foreignKey in table.foreignKeys {
                try? await logger?.logSchemaChange(
                    transactionId: transactionId,
                    operationType: .foreignKeyAdded,
                    tableName: table.name,
                    columnName: foreignKey.column,
                    metadata: [
                        "referencedTable": foreignKey.referencedTable,
                        "referencedColumn": foreignKey.referencedColumn
                    ]
                )
            }
        }

        for createIndexStatement in createIndexStatements {
            print(createIndexStatement)
            try self.run(createIndexStatement)
        }
        
        // Log index creations
        if let transactionId = currentTransactionId {
            for index in table.indexes {
                try? await logger?.logSchemaChange(
                    transactionId: transactionId,
                    operationType: .indexCreated,
                    tableName: table.name,
                    metadata: [
                        "indexName": index.name,
                        "isUnique": index.isUnique,
                        "columns": index.columns
                    ]
                )
            }
        }
    }
    
    func getUserDefinedTables() throws -> [ExistingSchema.Table]
    {
        let tables = try pragma("table_list", expecting: ExistingSchema.Table.self)
        return tables.filter { $0.isUserDefined }
    }

    func getColumns(tableName: String) throws -> [ExistingSchema.Column]
    {
        try pragma("table_info(\(tableName))", expecting: ExistingSchema.Column.self)
    }

    func getIndexes(tableName: String) throws -> [ExistingSchema.Index]
    {
        var indexes = [ExistingSchema.Index]()
        
        let indexesWithoutColumns = try pragma("index_list(\(tableName))", expecting: ExistingSchema.Index.self)
        
        for indexWithoutColumn in indexesWithoutColumns {
            let columnsInIndex = try pragma("index_info(\(indexWithoutColumn.name));", expecting: ExistingSchema.IndexColumn.self)
            indexes.append(indexWithoutColumn.withColumns(columnsInIndex))
        }
        
        return indexes
    }

    func createIndexStatements(for table: RequiredSchema.Table) -> [String]
    {
        var createIndexStatements = [String]()
        
        for index in table.indexes {
            let statement = "CREATE INDEX \(index.name) ON \(table.name)(\(index.columns.joined(separator: ", ")));"
            createIndexStatements.append(statement)
        }
        
        return createIndexStatements
    }
    
    func createTableStatement(for table: RequiredSchema.Table) -> String
    {
        var columns = [String]()
        var foreignKeys = [String]()

        for column in table.columns
        {
            let columnDefinition = "\"\(column.name)\" \(column.storageClass.rawValue.uppercased())"
            columns.append(columnDefinition)
        }
        
        for foreignKey in table.foreignKeys {
            let statement = "FOREIGN KEY (\(foreignKey.column)) REFERENCES \(foreignKey.referencedTable) (\(foreignKey.referencedColumn))"
            foreignKeys.append(statement)
        }

        let columnDefinitions = columns.joined(separator: ",\n    ")
        let foreignKeyDefinitions = (foreignKeys + [""]).joined(separator: ",\n    ")

        let createTableStatement = """
        CREATE TABLE "\(table.name)" (
            \(columnDefinitions),
            \(foreignKeyDefinitions)
            PRIMARY KEY(id)
        ) STRICT, WITHOUT ROWID;
        """
        
        // Note: `STRICT` is required, because when creating a `Database.Row` to forward the fetched data to object initializers, the storage values are created by switching on the SQLite column type. STRICT ensures the column type is set.
                
        return createTableStatement
    }


    public func close() throws
    {
        guard !isClosed else { return }
        
        Task {
            // Close the logger first
            try? await logger?.close()
        }
        
        let result = sqlite3_close(self.connectionHandle)
        
        guard result == SQLiteStatus.ok else {
            throw Error.failedToClose(SQLiteStatus(result))
        }
        
        isClosed = true
    }
    
    public func registerNotificationProxy(_ proxy: ActorNotificationProxy)
    {
        notificationProxies.append(proxy)
    }
    
    /// Access the logger for custom logging operations
    public func getLogger() -> DatabaseLogger? {
        return logger
    }
    
    /// Get entries from the log within a specified date range
    public func getLogEntries(
        from startDate: Date? = nil,
        to endDate: Date? = nil,
        transactionId: UUID? = nil,
        tableName: String? = nil,
        limit: Int? = nil
    ) async throws -> [DatabaseLogger.LogEntry] {
        guard let logger else {
            return []
        }
        return try await logger.getEntries(
            from: startDate,
            to: endDate,
            transactionId: transactionId,
            tableName: tableName,
            limit: limit
        )
    }
    
    /// Get all transaction IDs within a date range
    public func getLogTransactions(
        from startDate: Date? = nil,
        to endDate: Date? = nil
    ) async throws -> [UUID] {
        guard let logger else {
            return []
        }
        return try await logger.getTransactions(from: startDate, to: endDate)
    }
    
    isolated deinit
    {
        if !isClosed {
            sqlite3_close(self.connectionHandle)
        }
        
        let logger = self.logger
        Task {
            try? await logger?.close()
        }
    }
}

extension Database: Equatable
{
    public static func == (lhs: Database, rhs: Database) -> Bool {
        ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
    }
}
