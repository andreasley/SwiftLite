import SQLite3
import Foundation

struct ConfigurationTable
{
    let tableName: String
    let connectionHandle: OpaquePointer?
    
    func setValue(key: String, value: SQLValue) throws
    {
        let sql = """
        INSERT OR REPLACE INTO \(tableName) (key, value)
        VALUES (?, ?)
        """
        
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(connectionHandle, sql, -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        
        guard let statement, prepareResult == SQLiteStatus.ok else {
            let errmsg = String(cString: sqlite3_errmsg(connectionHandle))
            throw Error.failedToSetConfigurationValue(key: key, message: errmsg)
        }
        
        sqlite3_bind_text(statement, 1, key, -1, SQLITE_TRANSIENT)
        
        value.bind(to: statement, at: 2)
        
        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_DONE else {
            let errmsg = String(cString: sqlite3_errmsg(connectionHandle))
            throw Error.failedToSetConfigurationValue(key: key, message: errmsg)
        }
    }
    
    func getValue(key: String) throws -> SQLValue?
    {
        let sql = "SELECT value FROM \(tableName) WHERE key = ?"
        
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(connectionHandle, sql, -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        
        guard let statement, prepareResult == SQLiteStatus.ok else {
            let errmsg = String(cString: sqlite3_errmsg(connectionHandle))
            throw Error.failedToGetConfigurationValue(key: key, message: errmsg)
        }
        
        sqlite3_bind_text(statement, 1, key, -1, SQLITE_TRANSIENT)
        
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        
        let columnType = sqlite3_column_type(statement, 0)
        switch columnType {
        case SQLITE_INTEGER:
            return .int(sqlite3_column_int64(statement, 0))
        case SQLITE_FLOAT:
            return .double(sqlite3_column_double(statement, 0))
        case SQLITE_TEXT:
            return .string(String(cString: sqlite3_column_text(statement, 0)))
        case SQLITE_BLOB:
            if let blobPointer = sqlite3_column_blob(statement, 0) {
                let blobSize = Int(sqlite3_column_bytes(statement, 0))
                let data = Data(bytes: blobPointer, count: blobSize)
                return .data(data)
            } else {
                return nil
            }
        case SQLITE_NULL:
            return .null
        default:
            return nil
        }
    }
    
    func getValue(key: String) throws -> UUID?
    {
        guard let value: SQLValue = try getValue(key: key), case .string(let uuidString) = value else {
            return nil
        }
        return UUID(uuidString: uuidString)
    }
    
    func getValue(key: String) throws -> Int64?
    {
        guard let value: SQLValue = try getValue(key: key), case .int(let int) = value else {
            return nil
        }
        return int
    }
    
    func getValue(key: String) throws -> String?
    {
        guard let value: SQLValue = try getValue(key: key), case .string(let string) = value else {
            return nil
        }
        return string
    }

    func getValue(key: String) throws -> Date?
    {
        guard let value: SQLValue = try getValue(key: key), case .double(let timestamp) = value else {
            return nil
        }
        return Date(timeIntervalSince1970: timestamp)
    }
}

extension ConfigurationTable
{
    public enum Error: LocalizedError {
        case failedToGetConfigurationValue(key: String, message: String)
        case failedToSetConfigurationValue(key: String, message: String)

        public var errorDescription: String? {
            return switch self {
            case .failedToGetConfigurationValue(let key, let message):
                "Failed to get configuration value '\(key)': \(message)"
            case .failedToSetConfigurationValue(let key, let message):
                "Failed to set configuration value '\(key)': \(message)"
            }
        }
    }
}
