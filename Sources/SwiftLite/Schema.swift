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
    public protocol AnyEntity
    {
        var name: String { get }
        var tableName: String { get }
        var properties: [Property] { get }
    }
    
    public struct Entity<T>: Sendable, AnyEntity
    {
        public let name: String
        public let tableName: String
        public let properties: [Property]

        public init(name: String, tableName: String, properties: [Property])
        {
            self.name = name
            self.tableName = tableName
            self.properties = properties
        }
    }
}

extension Schema
{
    public struct Property: Sendable
    {
        // TODO: Is all that really needed? KeyPath too?
        public let name: String
        public let columnName: String
        public let sqliteType: SQLiteStorageClass
        public let isPrimaryKey: Bool
        public let isUnique: Bool
        public let isIndexed: Bool
        
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
