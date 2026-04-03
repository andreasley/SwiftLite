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

        public func nonOptionalValue<T>(_ value: T?, fallback: T?, error: Swift.Error = StorageConversionError.unexpectedNull) throws -> T
        {
            if let value {
                return value
            } else if let fallback {
                return fallback
            } else {
                throw error
            }
        }

        public func nonOptionalValue<T>(_ value: T?, fallback: T?, error: Swift.Error = StorageConversionError.unexpectedNull) throws -> T where T: Storable
        {
            if let value {
                return value
            } else if let fallback {
                return fallback
            } else if let globalFallback = T.fallbackValue {
                return globalFallback
            } else {
                throw error
            }
        }

        public func get<T>(_ name: String, as type: T.Type = T.self, fallback: T? = nil) throws -> T where T: Storable
        {
            let value: T? = try get(name)
            return try nonOptionalValue(value, fallback: fallback)
        }
        
        public func get<T>(_ name: String, as type: T.Type = T.self) throws -> T? where T: Storable
        {
            guard let sqlValue = columns[name] else { return nil }
            return try T(sqlValue: sqlValue)
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
        
        // MARK: Related collection (many to many) in Snapshot
        
        public func get<Schema: RelationshipModelSchema>(schema: Schema.Type = Schema.self, parentId: UUID) async throws -> [Schema.Element.Snapshot]
        {
            let junctionTableName = ManyToMany<Schema>.JunctionModel.Schema.table.name
            let preset = SQLStatementPreset.Select(table: junctionTableName, columns: ["element"], conditions: .byParent(parentId))
            let result = try await db.execute(preset.sqlStatement)
            
            var ids = [UUID]()
            for row in result {
                let id: UUID = try row.get("element")
                ids.append(id)
            }
            
            guard ids.count > 0 else { return [] }
            
            return try await db.find(Schema.Element.Snapshot.self, condition: .byId(in: ids))
        }
    }
}
