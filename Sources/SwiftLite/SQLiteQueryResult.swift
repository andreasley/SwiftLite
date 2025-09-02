import SQLite3

public class SQLiteQueryResult
{
    private let statement: OpaquePointer
    
    init(statement: OpaquePointer)
    {
        self.statement = statement
    }
    
    @inline(__always) public func getStoredValue<T>(index: Int32, as type: T.Type = T.self) throws -> T where T: StorageConvertible.Text
    {
        let value: UnsafePointer<UInt8>! = sqlite3_column_text(statement, index)
        let string = String(cString: value)
        return try T(storageValue: string)
    }

    @inline(__always) public func getStoredValue<T>(index: Int32, as type: T.Type = T.self) throws -> T where T: StorageConvertible.Integer
    {
        let value = sqlite3_column_int64(statement, index)
        return try T(storageValue: value)
    }

    @inline(__always) public func getStoredValue<T>(index: Int32, as type: T.Type = T.self) throws -> T where T: StorageConvertible.Real
    {
        let value = sqlite3_column_double(statement, index)
        return try T(storageValue: value)
    }

    @inline(__always) public func getStoredValue<T>(index: Int32, as type: T.Type = T.self) throws -> T where T: StorageConvertible.Blob
    {
        let value: UnsafeRawPointer = sqlite3_column_blob(statement, index)
        return try T(storageValue: value)
    }
}
