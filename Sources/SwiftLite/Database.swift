import SQLite3
import Foundation

public struct Database
{
    public enum StorageType {
        case file(URL)
        case inMemory
    }
    
    enum Error: Swift.Error, CustomStringConvertible, Sendable, Equatable {
        case failedToOpen(SQLiteStatus)
        case failedToClose(SQLiteStatus)
        case notAFileUrl(URL)

        var description: String {
            return switch self {
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
        
        let result = sqlite3_open_v2(filename, &pointer, flags.reduce(0, |), nil)
        
        guard let pointer, result == SQLiteStatus.ok else {
            throw Error.failedToOpen(SQLiteStatus(result))
        }
        
        self.connectionHandle = pointer
    }
    
    public func close() throws
    {
        let result = sqlite3_close(self.connectionHandle)
        
        guard result == SQLiteStatus.ok else {
            throw Error.failedToClose(SQLiteStatus(result))
        }
    }
}
