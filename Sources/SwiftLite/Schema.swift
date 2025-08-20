import Synchronization

public final class Schema: @unchecked Sendable // TODO: Implement proper Sendable
{
    public static let `default` = Schema()
    
    var entities = Array<AnyEntity>()
    
    public init() {}
    
    public func register(_ entity: AnyEntity)
    {
        self.entities.append(entity)
    }
}


extension Schema
{
    public protocol AnyEntity {}
    
    public struct Entity<T>: Sendable, AnyEntity
    {
        let properties: [Property]

        public init(properties: [Property])
        {
            self.properties = properties
        }

        public struct Property: Sendable
        {
            // TODO: Is all that really needed? KeyPath too?
            let name: String
            let type: Any.Type
            let column: String
            let sqliteType: SQLiteStorageClass
            let isPrimaryKey: Bool
            let isUnique: Bool
            let isIndexed: Bool
            
            public init(name: String, column: String, isPrimaryKey: Bool, isUnique: Bool, isIndexed: Bool)
            {
                self.name = name
                self.type = String.self // TODO
                self.column = column
                self.sqliteType = .text // TODO
                self.isPrimaryKey = isPrimaryKey
                self.isUnique = isUnique
                self.isIndexed = isIndexed
            }
        }
    }
}
