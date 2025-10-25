import SQLite3
import Foundation

public struct Database
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
        case queryFailed(query: String, status: SQLiteStatus, errorMessage: String)
        case failedToOpen(SQLiteStatus)
        case failedToClose(SQLiteStatus)
        case notAFileUrl(URL)

        var description: String {
            return switch self {
            case .queryFailed(let query, let status, let errorMessage):
                "Query `\(query)` failed: \(status.description) (\(errorMessage))"
            case .failedToOpen(let status):
                "Failed to open database: \(status.description))"
            case .failedToClose(let status):
                "Failed to close database: \(status.description)"
            case .notAFileUrl(let url):
                "URL \(url) is not a file URL"
            }
        }
    }
    
    internal let connectionHandle: OpaquePointer

    public init(storage: StorageType, cacheSizeLimit: CacheSize? = nil) throws
    {
        var pointer: OpaquePointer?
        var flags = [SQLITE_OPEN_READWRITE, SQLITE_OPEN_CREATE]
        var filename: String?
        
        if case .file(let url) = storage {
            guard url.isFileURL else {
                throw Error.notAFileUrl(url)
            }
            let filenameFromUrl = url.absoluteString
            filename = filenameFromUrl
            print("Opening database at \(filenameFromUrl)")
        } else if case .inMemory = storage {
            flags.append(SQLITE_OPEN_MEMORY)
            print("Opening database in memory")
        }
        
        let openStatus = sqlite3_open_v2(filename, &pointer, flags.reduce(0, |), nil)
        
        guard let pointer, openStatus == SQLiteStatus.ok else {
            throw Error.failedToOpen(SQLiteStatus(openStatus))
        }
        
        self.connectionHandle = pointer
        
        if let cacheSizeLimit {
            let limit = switch cacheSizeLimit {
            case .megabytes(let value): -value * 1024
            case .pages(let value): value
            }
            try executeOneStep("PRAGMA cache_size = \(limit)")
        }

        // "Foreign key constraints are disabled by default (for backwards compatibility), so must be enabled separately for each database connection" (https://sqlite.org/foreignkeys.html).
        try executeOneStep("PRAGMA foreign_keys = ON")
        
        try executeOneStep("PRAGMA journal_mode = WAL")
        
        // TODO: Compare schema and migrate if necessary
    }
    
    public func register(models: any Model.Type...) throws
    {
        try self.register(models: models)
    }

    public func register(models: [any Model.Type]) throws
    {
        // TODO:
        // 1. Build model graph (to find referenced model types and dependencies)
        // 2. Check if table(s) exists already
        //  if yes:
        //      1. Compare schema (positions, names and types should match; not sure about "STRICT" and "WITHOUT ROWID")
        //          if schema matches, continue
        //          if schema doesn't match, execute migration to new schema (traversing the graph upwards)
        //  if no:
        //      1. create table (traversing the graph upwards)
        
        let existingTables = try getUserDefinedTables()
        var tablesWithoutMatchingModels = Set(existingTables)
        
        for model in models {
            print("Checking table \(model.table.name)...")
            let existingTableForModel = existingTables.first { $0.name == model.table.name }
            if let existingTableForModel {
                print("exists; comparing...")
                tablesWithoutMatchingModels.remove(existingTableForModel)
                // compare schema
                try updateTableIfNecessary(existingTable: existingTableForModel, model: model)
            } else {
                print("doesn't exist; creating...")
                try createTable(model: model)
            }
        }
        
        for tablesWithoutMatchingModel in tablesWithoutMatchingModels {
            print("Ignoring user-defined table that doesn't map to any model: \(tablesWithoutMatchingModel.name)")
        }
    }
    
    public func executeOneStep(_ query: String) throws
    {
        let result = sqlite3_exec(self.connectionHandle, query, nil, nil, nil)
        guard result == SQLiteStatus.ok else {
            let errmsg = String(cString: sqlite3_errmsg(self.connectionHandle))
            print("Error while executing query: \(errmsg)")
            throw Error.queryFailed(query: query, status: SQLiteStatus(result), errorMessage: errmsg)
        }
    }
    
    public func execute<T: InitializableFromResultRow>(_ query: String, expecting: T.Type = T.self) throws -> [T]
    {
        var statement: OpaquePointer?
        
        let result = sqlite3_prepare_v2(self.connectionHandle, query, -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        
        guard result == SQLiteStatus.ok else  {
            let errmsg = String(cString: sqlite3_errmsg(self.connectionHandle))
            print("Error while executing query: \(errmsg)")
            throw Error.queryFailed(query: query, status: SQLiteStatus(result), errorMessage: errmsg)
        }
        
        var results = [T]()
        
        // TODO: Log errors returned from `sqlite3_step()`. Also consider retrying for `SQLITE_BUSY` and `SQLITE_LOCKED` (after a delay).
        
        while sqlite3_step(statement) == SQLITE_ROW, let statement {
            let resultRow = SQLiteQueryResult(statement: statement)
            let object = try T(row: resultRow)
            results.append(object)
            
            // TODO: To throw here means a result can't be fetched if any field of any row can't be converted as expected. The alternative is to skip one row and log the problem. Decide which is better and implement accordingly.
        }
        
        return results
    }

    public func snapshots<T: Model>(for modelType: T.Type = T.self) throws -> [T.Snapshot]
    {
        let query = T.__defaultSelectStatement
        let objects: [T.Snapshot] = try execute(query)
        return objects
    }

    func updateTableIfNecessary(existingTable: ExistingSchema.Table, model: Model.Type) throws
    {
        // Compare columns
        let existingColumns = try getColumns(tableName: existingTable.name)

        for existingColumn in existingColumns {
            
        }
        
        // Compare indexes
        let existingIndexes = try getIndexes(tableName: existingTable.name)
    }
    
    func createTable(model: Model.Type) throws
    {
        let createTableStatement = createTableStatement(for: model.table)
        let createIndexStatements = createIndexStatements(for: model.table)
        print(createTableStatement)
        try self.executeOneStep(createTableStatement)

        for createIndexStatement in createIndexStatements {
            print(createIndexStatement)
            try self.executeOneStep(createIndexStatement)
        }
    }
    
    func getUserDefinedTables() throws -> [ExistingSchema.Table]
    {
        let tables = try execute("PRAGMA table_list;", expecting: ExistingSchema.Table.self)
        return tables.filter { $0.isUserDefined }

    }

    func getColumns(tableName: String) throws -> [ExistingSchema.Column]
    {
        try execute("PRAGMA table_info(\(tableName));", expecting: ExistingSchema.Column.self)
    }

    func getIndexes(tableName: String) throws -> [ExistingSchema.Index]
    {
        var indexes = [ExistingSchema.Index]()
        
        let indexesWithoutColumns = try execute("PRAGMA index_list(\(tableName));", expecting: ExistingSchema.Index.self)
        
        for indexWithoutColumn in indexesWithoutColumns {
            let columnsInIndex = try execute("PRAGMA index_info(\(indexWithoutColumn.name));", expecting: ExistingSchema.IndexColumn.self)
            indexes.append(indexWithoutColumn.withColumns(columnsInIndex))
        }
        
        return indexes
    }

    func createIndexStatements(for table: Schema.Table) -> [String]
    {
        var createIndexStatements = [String]()
        
        for index in table.indexes {
            let statement = "CREATE INDEX \(index.name) ON \(table.name)(\(index.columns.joined(separator: ", ")));"
            createIndexStatements.append(statement)
        }
        
        return createIndexStatements
    }
    
    func createTableStatement(for table: Schema.Table) -> String
    {
        // TODO: Handle references
        
        var columns = [String]()
        var primaryKeyColumns = [Int32:String]()

        for column in table.columns
        {
            var columnDefinition = "\"\(column.name)\" \(column.storageClass.rawValue.uppercased())"

            if let defaultValue = column.defaultValue {
                columnDefinition += " DEFAULT \(defaultValue)"
            }

            if !column.isNullable {
                columnDefinition += " NOT NULL"
            }

            if let positionInPrimaryKey = column.positionInPrimaryKey {
                primaryKeyColumns[positionInPrimaryKey] = column.name
            }
            
            columns.append(columnDefinition)
        }

        let columnDefinitions = columns.joined(separator: ",\n    ")
        let primaryKeyDefinition = primaryKeyColumns.sorted(by: { $0.key < $1.key }).map { $0.value }.joined(separator: ", ")

        let createTableStatement = """
        CREATE TABLE "\(table.name)" (
            \(columnDefinitions),
            PRIMARY KEY(\(primaryKeyDefinition))
        ) STRICT, WITHOUT ROWID;
        """
                
        return createTableStatement
    }


    public func close() throws
    {
        let result = sqlite3_close(self.connectionHandle)
        
        guard result == SQLiteStatus.ok else {
            throw Error.failedToClose(SQLiteStatus(result))
        }
    }
}
