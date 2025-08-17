import Synchronization

public final class Schema: @unchecked Sendable // TODO: Implement proper Sendable
{
    public static let `default` = Schema()
    
    var entities = Array<Entity>()
    
    public init() {}
    
    public func register(_ entity: Entity)
    {
        self.entities.append(entity)
    }
}

extension Schema
{
    public struct Entity: Sendable
    {
        let properties: [Property]

        public init(properties: [Property])
        {
            self.properties = properties
        }

        public struct Property: Sendable
        {
            let name: String
            let type: String // TODO: Find best way to reference a type for this
            let isPrimaryKey: Bool
            let isUnique: Bool
            let isIndexed: Bool
            
            public init(name: String, type: String, isPrimaryKey: Bool, isUnique: Bool, isIndexed: Bool)
            {
                self.name = name
                self.type = type
                self.isPrimaryKey = isPrimaryKey
                self.isUnique = isUnique
                self.isIndexed = isIndexed
            }
        }
    }
}
