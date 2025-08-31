//import Synchronization
//
//public final class Schema: @unchecked Sendable // TODO: Implement proper Sendable
//{
//    public static let `default` = Schema()
// 
//    // TODO: Is this actually needed or is a reference to the `Database` (which knows the entities) available wherever needed?
//    var entities = Array<AnyEntity>()
//    
//    public init() {}
//    
//    public func register(_ entity: AnyEntity)
//    {
//        self.entities.append(entity)
//    }
//}
//
//extension Schema
//{
//    public protocol AnyEntity
//    {
//        var name: String { get }
//        var tableName: String { get }
//        var properties: [Property] { get }
//    }
//    
//    public struct Entity: Sendable, AnyEntity
//    {
//        public let name: String
//        public let tableName: String
//        public let properties: [Property]
//
//        public init(name: String, tableName: String, properties: [Property])
//        {
//            self.name = name
//            self.tableName = tableName
//            self.properties = properties
//        }
//    }
//}
//
//extension Schema
//{
//    public struct Property: Sendable
//    {
//        // TODO: Is all that really needed? KeyPath too?
//        public let name: String
//        public let columnName: String
//        public let storageClass: StorageClass
//        public let isPrimaryKey: Bool
//        public let isUnique: Bool
//        public let isIndexed: Bool
//        public let isNullable: Bool
//
//        public init<T>(name: String, columnName: String, type: T.Type, isPrimaryKey: Bool, isUnique: Bool, isIndexed: Bool, isNullable: Bool)
//        {
//            self.name = name
//            self.columnName = columnName
//            self.storageClass = StorageClass(for: type)
//            self.isPrimaryKey = isPrimaryKey
//            self.isUnique = isUnique
//            self.isIndexed = isIndexed
//            self.isNullable = isNullable
//        }
//    }
//}
