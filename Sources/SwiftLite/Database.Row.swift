import SQLite3
import Foundation

public nonisolated extension Database
{
    struct Row: Sendable
    {
        let db: Database
        private let columns: [String: SQLValue]
        
        init(db: Database, statement: OpaquePointer)
        {
            self.db = db
            
            let count = sqlite3_column_count(statement)
            var columns = [String: SQLValue](minimumCapacity: Int(count))
            
            for i in 0..<count {
                let name = String(cString: sqlite3_column_name(statement, i))
                
                switch sqlite3_column_type(statement, i) {
                case SQLITE_INTEGER:
                    columns[name] = .int(sqlite3_column_int64(statement, i))
                case SQLITE_FLOAT:
                    columns[name] = .double(sqlite3_column_double(statement, i))
                case SQLITE_TEXT:
                    let cStr = sqlite3_column_text(statement, i)!
                    columns[name] = .string(String(cString: cStr))
                case SQLITE_BLOB:
                    if let ptr = sqlite3_column_blob(statement, i) {
                        let len = sqlite3_column_bytes(statement, i)
                        columns[name] = .data(Data(bytes: ptr, count: Int(len)))
                    }
                case SQLITE_NULL:
                    break
                default:
                    break
                }
            }
            
            self.columns = columns
        }

        @inline(__always) public func nonOptionalValue<T>(_ value: T?, fallback: T?, error: Swift.Error = StorageConvertible.ConversionError.unexpectedNull) throws -> T
        {
            if let value {
                return value
            } else if let fallback {
                return fallback
            } else {
                throw error
            }
        }

        // MARK: String
        
        @inline(__always) public func get<T>(_ name: String, as type: T.Type = T.self, fallback: T? = nil) throws -> T where T: StorageConvertible.Text
        {
            let value: T? = try get(name)
            return try nonOptionalValue(value, fallback: fallback)
        }
        
        @inline(__always) public func get<T>(_ name: String, as type: T.Type = T.self) throws -> T? where T: StorageConvertible.Text
        {
            guard case .string(let string) = columns[name] else { return nil }
            return try T(storageValue: string)
        }
        
        // MARK: Integer
        
        @inline(__always) public func get<T>(_ name: String, as type: T.Type = T.self, fallback: T? = nil) throws -> T where T: StorageConvertible.Integer
        {
            let value: T? = try get(name)
            return try nonOptionalValue(value, fallback: fallback)
        }
        
        @inline(__always) public func get<T>(_ name: String, as type: T.Type = T.self) throws -> T? where T: StorageConvertible.Integer
        {
            guard case .int(let int) = columns[name] else { return nil }
            return try T(storageValue: int)
        }
        
        // MARK: Real
        
        @inline(__always) public func get<T>(_ name: String, as type: T.Type = T.self, fallback: T? = nil) throws -> T where T: StorageConvertible.Real
        {
            let value: T? = try get(name)
            return try nonOptionalValue(value, fallback: fallback)
        }
        
        @inline(__always) public func get<T>(_ name: String, as type: T.Type = T.self) throws -> T? where T: StorageConvertible.Real
        {
            guard case .double(let double) = columns[name] else { return nil }
            return try T(storageValue: double)
        }
        
        // MARK: Blob
        
        @inline(__always) public func get<T>(_ name: String, as type: T.Type = T.self, fallback: T? = nil) throws -> T where T: StorageConvertible.Blob
        {
            let value: T? = try get(name)
            return try nonOptionalValue(value, fallback: fallback)
        }
        
        @inline(__always) public func get<T>(_ name: String, as type: T.Type = T.self) throws -> T? where T: StorageConvertible.Blob
        {
            guard case .data(let data) = columns[name] else { return nil }
            return try T(storageValue: data)
        }
        
        // MARK: Referenced Model or Snapshot
        
        public func get<T: Fetchable>(_ name: String, as type: sending T.Type = T.self, fallback: T? = nil) async throws -> T
        {
            let id: UUID = try get(name)
            let result = try await db.get(type, id: id)
            return try nonOptionalValue(result, fallback: fallback, error: Database.Error.failedToFindReferencedObject(table: T.Model.Schema.table.name, id: id))
        }
        
        public func get<T: Fetchable>(_ name: String, as type: sending T.Type = T.self) async throws -> T?
        {
            guard let id: UUID = try get(name) else { return nil }
            let result = try await db.get(type, id: id)
            return result
        }
            
        // MARK: Relation
        
        public func get<T: Model>(_ name: String, as type: sending T.Type = T.self, fallback: T? = nil) throws -> DirectRelationReference<T>
        {
            let id: UUID = try get(name)
            return DirectRelationReference(id: id)
        }
        
        public func get<T: Model>(_ name: String, as type: sending T.Type = T.self) throws -> DirectRelationReference<T>?
        {
            guard let id: UUID = try get(name) else { return nil }
            return DirectRelationReference(id: id)
        }
        
        // MARK: Related collection (many to many)
        
        public func get<Schema: RelationshipModelSchema>(parentId: UUID) async throws -> ManyToMany<Schema>
        {
            try await ManyToMany(db: db, parentId: parentId)
        }

        // MARK: Inverse related collection (many to one)
        
        public func get<ReferencingModel: ModelSnapshot, ReferencedModel: Model>(objectId: UUID, referencingField: String) async throws -> Inverse<ReferencingModel, ReferencedModel>
        {
            try await Inverse<ReferencingModel, ReferencedModel>(db: db, objectId: objectId, referencingField: referencingField)
        }

        // MARK: Inverse related collection (many to many)
        
        public func get<Schema: RelationshipModelSchema>(inverse keyPath: KeyPath<Schema.Parent, ManyToMany<Schema>>, db: Database, elementId: UUID) async throws -> InverseManyToMany<Schema>
        {
            try await InverseManyToMany(keyPath: keyPath, db: db, elementId: elementId)
        }
    }
}
