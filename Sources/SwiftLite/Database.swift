import SQLite3
import Foundation

public struct Database
{
    public enum StorageType {
        case file(URL)
        case inMemory
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
    
    public init(storage: StorageType) throws
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

        try execute("PRAGMA foreign_keys = ON")
        try execute("PRAGMA journal_mode = WAL")
        
        // TODO: Compare schema and migrate if necessary
    }
    
    public func close() throws
    {
        let result = sqlite3_close(self.connectionHandle)
        
        guard result == SQLiteStatus.ok else {
            throw Error.failedToClose(SQLiteStatus(result))
        }
    }
}
