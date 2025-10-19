import SQLite3

public class SQLiteQueryResult
{
    private let statement: OpaquePointer
    
    init(statement: OpaquePointer)
    {
        self.statement = statement
    }
    
    // MARK: String
    
    @inline(__always) public func getStoredValue<T>(index: Int32, as type: T.Type = T.self) throws -> T where T: StorageConvertible.Text
    {
        let value: T? = try getStoredValue(index: index)
        guard let value else { throw StorageConvertible.ConversionError.failedToConvert }
        return value
    }
    
    @inline(__always) public func getStoredValue<T>(index: Int32, as type: T.Type = T.self) throws -> T? where T: StorageConvertible.Text
    {
        guard let value = sqlite3_column_text(statement, index) else { return nil }
        let string = String(cString: value)
        return try T(storageValue: string)
    }
    
    // MARK: Integer
    
    @inline(__always) public func getStoredValue<T>(index: Int32, as type: T.Type = T.self) throws -> T where T: StorageConvertible.Integer
    {
        let value: T? = try getStoredValue(index: index)
        guard let value else { throw StorageConvertible.ConversionError.failedToConvert }
        return value
    }
    
    @inline(__always) public func getStoredValue<T>(index: Int32, as type: T.Type = T.self) throws -> T? where T: StorageConvertible.Integer
    {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        let value = sqlite3_column_int64(statement, index)
        return try T(storageValue: value)
    }
    
    // MARK: Real
    
    @inline(__always) public func getStoredValue<T>(index: Int32, as type: T.Type = T.self) throws -> T where T: StorageConvertible.Real
    {
        let value: T? = try getStoredValue(index: index)
        guard let value else { throw StorageConvertible.ConversionError.failedToConvert }
        return value
    }
    
    @inline(__always) public func getStoredValue<T>(index: Int32, as type: T.Type = T.self) throws -> T? where T: StorageConvertible.Real
    {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        let value = sqlite3_column_double(statement, index)
        return try T(storageValue: value)
    }
    
    // MARK: Blob
    
    @inline(__always) public func getStoredValue<T>(index: Int32, as type: T.Type = T.self) throws -> T where T: StorageConvertible.Blob
    {
        let value: T? = try getStoredValue(index: index)
        guard let value else { throw StorageConvertible.ConversionError.failedToConvert }
        return value
    }
    
    @inline(__always) public func getStoredValue<T>(index: Int32, as type: T.Type = T.self) throws -> T? where T: StorageConvertible.Blob
    {
        guard let value: UnsafeRawPointer = sqlite3_column_blob(statement, index) else { return nil }
        return try T(storageValue: value)
    }
}
