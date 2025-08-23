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
        let name: String
        let tableName: String
        let properties: [Property]

        public init(name: String, tableName: String, properties: [Property])
        {
            self.name = name
            self.tableName = tableName
            self.properties = properties
        }

        public struct Property: Sendable
        {
            // TODO: Is all that really needed? KeyPath too?
            let name: String
            let columnName: String
            let sqliteType: SQLiteStorageClass
            let isPrimaryKey: Bool
            let isUnique: Bool
            let isIndexed: Bool
            
            public init(name: String, columnName: String, sqliteType: SQLiteStorageClass, isPrimaryKey: Bool, isUnique: Bool, isIndexed: Bool)
            {
                self.name = name
                self.columnName = columnName
                self.sqliteType = sqliteType
                self.isPrimaryKey = isPrimaryKey
                self.isUnique = isUnique
                self.isIndexed = isIndexed
            }
        }
    }
}
