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
        case queryFailed(String, SQLiteStatus)
        case failedToOpen(SQLiteStatus)
        case failedToClose(SQLiteStatus)
        case notAFileUrl(URL)

        var description: String {
            return switch self {
            case .queryFailed(let query, let status):
                "Query `\(query)` failed: \(status.description))"
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
    
    func execute(_ query: String) throws
    {
        let result = sqlite3_exec(self.connectionHandle, query, nil, nil, nil)
        guard result == SQLiteStatus.ok else {
            throw Error.queryFailed(query, SQLiteStatus(result))
        }
    }
    
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
            try execute("PRAGMA cache_size = \(limit)")
        }

        try execute("PRAGMA foreign_keys = ON")
        try execute("PRAGMA journal_mode = WAL")
        
        // TODO: Compare schema and migrate if necessary
    }
    
    public func register(models: any Model.Type...)
    {
        self.register(models: models)
    }

    public func register(models: [any Model.Type])
    {
        // TODO:
        // 1. Build model graph (to find referenced model types and dependencies)
        // 2. Check if table(s) exists already
        //  if yes:
        //      1. Compare schema
        //          if schema matches, continue
        //          if schema doesn't match, execute migration to new schema (traversing the graph upwards)
        //  if no:
        //      1. create table (traversing the graph upwards)
        
        for model in models {
            let createTableStatement = createTableStatement(for: model.entity)
            let createIndexStatements = createIndexStatements(for: model.entity)
            print(createTableStatement)
            try? self.execute(createTableStatement)
            
            for createIndexStatement in createIndexStatements {
                print(createIndexStatement)
                try? self.execute(createIndexStatement)
            }
        }
    }
    
    func createIndexStatements(for entity: Schema.Entity) -> [String]
    {
        // TODO: Implement indexes over multiple columns
        
        var createIndexStatements = [String]()
        
        for property in entity.properties where property.isIndexed {
            let statement = "CREATE INDEX IF NOT EXISTS idx_\(entity.tableName)_\(property.columnName) ON \(entity.tableName)(\(property.columnName));"
            createIndexStatements.append(statement)
        }
        
        return createIndexStatements
    }
    
    func createTableStatement(for entity: Schema.Entity) -> String
    {
        // TODO: Handle references
        
        var columns = [String]()

        for property in entity.properties
        {
            var columnDefinition = "\"\(property.columnName)\" \(property.storageClass.rawValue.uppercased())"
            
            if property.isPrimaryKey {
                columnDefinition += " PRIMARY KEY"
            }
            if property.isUnique {
                columnDefinition += " UNIQUE"
            }
            if !property.isNullable {
                columnDefinition += " NOT NULL"
            }
            
            columns.append(columnDefinition)
        }

        let columnDefinitions = columns.joined(separator: ",\n    ")
        let createTableStatement = """
        CREATE TABLE IF NOT EXISTS "\(entity.tableName)" (
            \(columnDefinitions)
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
