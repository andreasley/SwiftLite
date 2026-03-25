import Foundation
import SQLite3

public nonisolated struct SQLiteQueryResult: ~Copyable
{
    let db: Database
    private let statement: OpaquePointer
    
    init(db: Database, statement: OpaquePointer)
    {
        self.db = db
        self.statement = statement
    }
        
    // MARK: String
    
    public func get<T>(_ index: Int32, as type: T.Type = T.self) throws -> T where T: StorageConvertible.Text
    {
        let value: T? = try get(index)
        guard let value else { throw StorageConvertible.ConversionError.failedToConvert }
        return value
    }
    
    public func get<T>(_ index: Int32, as type: T.Type = T.self) throws -> T? where T: StorageConvertible.Text
    {
        guard let value = sqlite3_column_text(statement, index) else { return nil }
        let string = String(cString: value)
        return try T(storageValue: string)
    }
    
    // MARK: Integer
    
    public func get<T>(_ index: Int32, as type: T.Type = T.self) throws -> T where T: StorageConvertible.Integer
    {
        let value: T? = try get(index)
        guard let value else { throw StorageConvertible.ConversionError.failedToConvert }
        return value
    }
    
    public func get<T>(_ index: Int32, as type: T.Type = T.self) throws -> T? where T: StorageConvertible.Integer
    {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        let value = sqlite3_column_int64(statement, index)
        return try T(storageValue: value)
    }
    
    // MARK: Real
    
    public func get<T>(_ index: Int32, as type: T.Type = T.self) throws -> T where T: StorageConvertible.Real
    {
        let value: T? = try get(index)
        guard let value else { throw StorageConvertible.ConversionError.failedToConvert }
        return value
    }
    
    public func get<T>(_ index: Int32, as type: T.Type = T.self) throws -> T? where T: StorageConvertible.Real
    {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        let value = sqlite3_column_double(statement, index)
        return try T(storageValue: value)
    }
    
    // MARK: Blob
    
    public func get<T>(_ index: Int32, as type: T.Type = T.self) throws -> T where T: StorageConvertible.Blob
    {
        let value: T? = try get(index)
        guard let value else { throw StorageConvertible.ConversionError.failedToConvert }
        return value
    }
    
    public func get<T>(_ index: Int32, as type: T.Type = T.self) throws -> T? where T: StorageConvertible.Blob
    {
        guard let value: UnsafeRawPointer = sqlite3_column_blob(statement, index) else { return nil }
        let byteCount = Int(sqlite3_column_bytes(statement, index))
        let data = Data(bytes: value, count: byteCount)
        return try T(storageValue: data)
    }
    
    // MARK: Referenced Model or Snapshot
    
    public func get<T: Fetchable>(_ index: Int32, as type: sending T.Type = T.self) async throws -> T
    {
        let id: UUID = try get(index)
        let result = try await db.get(type, id: id)
        guard let result else { throw Database.Error.failedToFindReferencedObject(table: T.Model.Schema.table.name, id: id)}
        return result
    }
    
    public func get<T: Fetchable>(_ index: Int32, as type: sending T.Type = T.self) async throws -> T?
    {
        guard let id: UUID = try get(index) else { return nil }
        let result = try await db.get(type, id: id)
        return result
    }
        
    // MARK: Relation
    
    public func get<T: Model>(_ index: Int32, as type: sending T.Type = T.self) throws -> DirectRelationReference<T>
    {
        let id: UUID = try get(index)
        return DirectRelationReference(id: id)
    }
    
    public func get<T: Model>(_ index: Int32, as type: sending T.Type = T.self) throws -> DirectRelationReference<T>?
    {
        guard let id: UUID = try get(index) else { return nil }
        return DirectRelationReference(id: id)
    }

}
