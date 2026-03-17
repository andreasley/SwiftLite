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
    public private(set) var logger: DatabaseLogger?
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
            let transactionId = UUID()
            currentTransactionId = transactionId
            
            print("▶️ BEGINNING SCHEMA UPDATE TRANSACTION")
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
                print("✅ COMMITTED SCHEMA UPDATE TRANSACTION")
                // Transaction succeeded - logging happened during operations
            } catch {
                try? self.run("ROLLBACK")
                print("✴️ ROLLED BACK SCHEMA UPDATE TRANSACTION")
                // Failed transaction - don't log, just clean up
                currentTransactionId = nil
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
            print("▶️ BEGINNING READ TRANSACTION")
            let associatedData = ReadAssociatedData(db: self)
            
            try await ReadAssociatedData.$current.withValue(associatedData) {
                try await self.run("BEGIN")
                do {
                    results = try await body()
                    try await self.run("COMMIT")
                    print("✅ COMMITTED READ TRANSACTION")
                } catch {
                    try? await self.run("ROLLBACK")
                    print("✴️ ROLLED BACK READ TRANSACTION")
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
            let transactionId = UUID()
            currentTransactionId = transactionId
            
            print("▶️ BEGINNING WRITE TRANSACTION")
            var transactionCompletedSuccessfully = false
            try self.run("BEGIN")
            do {
                try self.setPragma(name: "defer_foreign_keys", value: "ON") // to wait with enforcement until `COMMIT`

                for object in changeset.changes {
                    let byObjectId = SQLCondition(field: "id", value: object.objectId.convertToSQLValue())
                    
                    switch object.status {
                    case .created:
                        guard let updatedFields = object.updatedFields else { continue }
                        let preset = SQLStatementPreset.Insert(table: object.table, updatedFields: updatedFields)
                        try self.execute(preset.sqlStatement)
                    case .deleted:
                        let preset = SQLStatementPreset.Delete(table: object.table, conditions: [byObjectId])
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
                
                // Transaction succeeded - now log all the changes
                for object in changeset.changes {
                    try? await logger?.logDataChange(transactionId: transactionId, change: object)
                }
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
        
        // Log table creation (granular: just the table itself)
        if let transactionId = currentTransactionId {
            try? await logger?.logSchemaChange(
                transactionId: transactionId,
                operationType: .tableCreated,
                tableName: table.name
            )
            
            // Log each column addition separately
            for column in table.columns {
                var metadata: [String: String] = ["storageClass": column.storageClass.rawValue]
                
                // Include referenced table if this column has a foreign key
                if let referencedTable = column.referencedTable {
                    metadata["referencedTable"] = referencedTable
                    metadata["referencedColumn"] = "id"
                }
                
                try? await logger?.logSchemaChange(
                    transactionId: transactionId,
                    operationType: .columnAdded,
                    tableName: table.name,
                    columnName: column.name,
                    metadata: metadata
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

        for column in table.columns
        {
            
            // Check if this column has a foreign key reference
            if let referencedTable = column.referencedTable {
                let columnDefinition = "\"\(column.name)\" \(column.storageClass.rawValue.uppercased()) REFERENCES \(referencedTable) (id)"
                columns.append(columnDefinition)
            } else {
                let columnDefinition = "\"\(column.name)\" \(column.storageClass.rawValue.uppercased())"
                columns.append(columnDefinition)
            }
        }

        let columnDefinitions = columns.joined(separator: ",\n    ")

        let createTableStatement = """
        CREATE TABLE "\(table.name)" (
            \(columnDefinitions),
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
    
    /// Process external log entries received from distributed sync
    /// - Parameter entries: Array of log entries grouped by transaction ID
    /// - Note: Entries should be sorted by timestamp and grouped by transaction
    public func processExternalLogEntries(_ entries: [DatabaseLogger.LogEntry]) async throws {
        guard !entries.isEmpty else { return }
        
        // Group entries by transaction ID
        let groupedByTransaction = Dictionary(grouping: entries) { $0.transactionId }
        
        // Sort transaction IDs by the earliest timestamp in each group
        let sortedTransactionIds = groupedByTransaction.keys.sorted { transactionId1, transactionId2 in
            let firstTimestamp1 = groupedByTransaction[transactionId1]?.first?.timestamp ?? Date.distantPast
            let firstTimestamp2 = groupedByTransaction[transactionId2]?.first?.timestamp ?? Date.distantPast
            return firstTimestamp1 < firstTimestamp2
        }
        
        // Process each transaction in order
        for transactionId in sortedTransactionIds {
            guard let transactionEntries = groupedByTransaction[transactionId] else { continue }
            
            // Sort entries within transaction by timestamp
            let sortedEntries = transactionEntries.sorted { $0.timestamp < $1.timestamp }
            
            try await processTransaction(entries: sortedEntries, transactionId: transactionId)
        }
    }
    
    /// Process a single transaction's worth of log entries
    private func processTransaction(entries: [DatabaseLogger.LogEntry], transactionId: UUID) async throws {
        try await gate.run {
            print("▶️ BEGINNING EXTERNAL LOG REPLAY TRANSACTION (\(transactionId))")
            
            // Group by operation type to handle schema changes first
            let schemaEntries = entries.filter { entry in
                switch entry.operationType {
                case .tableCreated,
                     .columnAdded,
                     .indexCreated,
                     .indexDropped:
                    return true
                default:
                    return false
                }
            }
            
            let dataEntries = entries.filter { entry in
                switch entry.operationType {
                case .rowCreated, 
                     .rowDeleted, 
                     .fieldUpdated:
                    return true
                default:
                    return false
                }
            }
            
            // Process schema changes first
            if !schemaEntries.isEmpty {
                try await processSchemaEntries(schemaEntries, transactionId: transactionId)
            }
            
            // Then process data changes
            if !dataEntries.isEmpty {
                try await processDataEntries(dataEntries, transactionId: transactionId)
            }
            
            print("✅ COMPLETED EXTERNAL LOG REPLAY TRANSACTION (\(transactionId))")
        }
    }
    
    /// Process schema change log entries
    private func processSchemaEntries(_ entries: [DatabaseLogger.LogEntry], transactionId: UUID) async throws {
        try self.run("BEGIN")
        
        do {
            for entry in entries {
                guard let tableName = entry.tableName else {
                    print("⚠️ Skipping schema entry without table name: \(entry.operationType)")
                    continue
                }
                
                switch entry.operationType {
                case DatabaseLogger.OperationType.tableCreated:
                    print("📋 Replaying: Table created - \(tableName)")
                    // Table creation is complex and requires full schema info
                    // For now, we'll just note it - actual table creation should happen via register()
                    // This entry serves as an audit trail
                    
                case DatabaseLogger.OperationType.columnAdded:
                    guard let columnName = entry.columnName else {
                        print("⚠️ Skipping column addition without column name")
                        continue
                    }
                    
                    // Extract storage class from metadata
                    var storageClass = "TEXT" // default
                    if let metadataJSON = entry.metadata,
                       let metadataData = metadataJSON.data(using: .utf8),
                       let metadata = try? JSONSerialization.jsonObject(with: metadataData) as? [String: Any],
                       let storageClassValue = metadata["storageClass"] as? String {
                        storageClass = storageClassValue.uppercased()
                    }
                    
                    print("📋 Replaying: Column added - \(tableName).\(columnName) (\(storageClass))")
                    
                    // Check if column already exists
                    let existingColumns = try getColumns(tableName: tableName)
                    if !existingColumns.contains(where: { $0.name == columnName }) {
                        let alterStatement = "ALTER TABLE \"\(tableName)\" ADD COLUMN \"\(columnName)\" \(storageClass)"
                        try run(alterStatement)
                    } else {
                        print("ℹ️ Column \(tableName).\(columnName) already exists, skipping")
                    }
                    
                case DatabaseLogger.OperationType.indexCreated:
                    guard let metadataJSON = entry.metadata,
                          let metadataData = metadataJSON.data(using: .utf8),
                          let metadata = try? JSONSerialization.jsonObject(with: metadataData) as? [String: Any],
                          let indexName = metadata["indexName"] as? String,
                          let columns = metadata["columns"] as? [String] else {
                        print("⚠️ Skipping index creation without required metadata")
                        continue
                    }
                    
                    let isUnique = (metadata["isUnique"] as? Bool) ?? false
                    
                    print("📋 Replaying: Index created - \(indexName) on \(tableName)")
                    
                    // Check if index already exists
                    let existingIndexes = try getIndexes(tableName: tableName)
                    if !existingIndexes.contains(where: { $0.name == indexName }) {
                        let uniqueKeyword = isUnique ? "UNIQUE " : ""
                        let createIndexStatement = "CREATE \(uniqueKeyword)INDEX \"\(indexName)\" ON \"\(tableName)\"(\(columns.joined(separator: ", ")))"
                        try run(createIndexStatement)
                    } else {
                        print("ℹ️ Index \(indexName) already exists, skipping")
                    }
                    
                case DatabaseLogger.OperationType.indexDropped:
                    guard let metadataJSON = entry.metadata,
                          let metadataData = metadataJSON.data(using: .utf8),
                          let metadata = try? JSONSerialization.jsonObject(with: metadataData) as? [String: Any],
                          let indexName = metadata["indexName"] as? String else {
                        print("⚠️ Skipping index drop without index name")
                        continue
                    }
                    
                    print("📋 Replaying: Index dropped - \(indexName)")
                    
                    // Check if index exists before dropping
                    let existingIndexes = try getIndexes(tableName: tableName)
                    if existingIndexes.contains(where: { $0.name == indexName }) {
                        try run("DROP INDEX \"\(indexName)\"")
                    } else {
                        print("ℹ️ Index \(indexName) doesn't exist, skipping")
                    }
                    
                default:
                    break
                }
            }
            
            try self.run("COMMIT")
            print("✅ COMMITTED SCHEMA REPLAY TRANSACTION")
        } catch {
            try? self.run("ROLLBACK")
            print("✴️ ROLLED BACK SCHEMA REPLAY TRANSACTION")
            throw error
        }
    }
    
    /// Process data change log entries
    private func processDataEntries(_ entries: [DatabaseLogger.LogEntry], transactionId: UUID) async throws {
        try self.run("BEGIN")
        
        do {
            try self.setPragma(name: "defer_foreign_keys", value: "ON")
            
            // Group data entries by object ID to reconstruct operations
            // Use a custom key type that conforms to Hashable
            struct ObjectKey: Hashable {
                let tableName: String
                let objectId: UUID
            }
            
            let groupedByObject = Dictionary(grouping: entries.compactMap { entry -> (ObjectKey, DatabaseLogger.LogEntry)? in
                guard let tableName = entry.tableName, let objectId = entry.objectId else {
                    return nil
                }
                return (ObjectKey(tableName: tableName, objectId: objectId), entry)
            }) { $0.0 }
            
            for (key, keyedEntries) in groupedByObject {
                let tableName = key.tableName
                let objectId = key.objectId
                let objectEntries = keyedEntries.map { $0.1 }
                
                let sortedObjectEntries = objectEntries.sorted { $0.timestamp < $1.timestamp }
                
                // Determine the operation type
                let hasRowCreated = sortedObjectEntries.contains { $0.operationType == DatabaseLogger.OperationType.rowCreated }
                let hasRowDeleted = sortedObjectEntries.contains { $0.operationType == DatabaseLogger.OperationType.rowDeleted }
                let fieldUpdates = sortedObjectEntries.filter { $0.operationType == DatabaseLogger.OperationType.fieldUpdated }
                
                if hasRowDeleted {
                    // Delete operation
                    print("📋 Replaying: Row deleted - \(tableName)[\(objectId)]")
                    let deleteStatement = SQLStatementPreset.Delete(
                        table: tableName,
                        conditions: [SQLCondition(field: "id", value: .string(objectId.uuidString))]
                    )
                    try? execute(deleteStatement.sqlStatement) // Use try? to avoid errors if row doesn't exist
                    
                } else if hasRowCreated {
                    // Create operation - collect all field values
                    var fields: [String: SQLValue] = ["id": .string(objectId.uuidString)]
                    
                    for fieldUpdate in fieldUpdates {
                        guard let columnName = fieldUpdate.columnName,
                              let newValue = fieldUpdate.newValue else { continue }
                        fields[columnName] = parseValueString(newValue)
                    }
                    
                    print("📋 Replaying: Row created - \(tableName)[\(objectId)] with \(fields.count) fields")
                    
                    let insertStatement = SQLStatementPreset.Insert(table: tableName, updatedFields: fields)
                    try? execute(insertStatement.sqlStatement) // Use try? to handle conflicts
                    
                } else if !fieldUpdates.isEmpty {
                    // Update operation - apply field changes
                    var fields: [String: SQLValue] = [:]
                    
                    for fieldUpdate in fieldUpdates {
                        guard let columnName = fieldUpdate.columnName,
                              let newValue = fieldUpdate.newValue else { continue }
                        fields[columnName] = parseValueString(newValue)
                    }
                    
                    if !fields.isEmpty {
                        print("📋 Replaying: Row updated - \(tableName)[\(objectId)] with \(fields.count) fields")
                        
                        let updateStatement = SQLStatementPreset.Update(
                            table: tableName,
                            updatedFields: fields,
                            condition: SQLCondition(field: "id", value: .string(objectId.uuidString))
                        )
                        try? execute(updateStatement.sqlStatement) // Use try? to avoid errors if row doesn't exist
                    }
                }
            }
            
            try self.run("COMMIT")
            print("✅ COMMITTED DATA REPLAY TRANSACTION")
        } catch {
            try? self.run("ROLLBACK")
            print("✴️ ROLLED BACK DATA REPLAY TRANSACTION")
            throw error
        }
    }
    
    /// Parse a string value back into SQLValue
    /// This reverses the sqlValueToString operation in DatabaseLogger
    private func parseValueString(_ valueString: String) -> SQLValue {
        // Try to parse as different types
        if valueString == "NULL" {
            return .null
        }
        
        // Try as integer
        if let intValue = Int64(valueString) {
            return .int(intValue)
        }
        
        // Try as double
        if let doubleValue = Double(valueString) {
            return .double(doubleValue)
        }
        
        // Try as base64-encoded data
        if let data = Data(base64Encoded: valueString) {
            return .data(data)
        }
        
        // Default to string
        return .string(valueString)
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
