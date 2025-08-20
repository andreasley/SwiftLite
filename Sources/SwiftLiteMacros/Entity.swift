
public struct Entity: Sendable
{
    let properties: [Property]

    public init(properties: [Property])
    {
        self.properties = properties
    }

    public struct Property: Sendable
    {
        // TODO: Is all that really needed? KeyPath too?
        let propertyName: String
        let type: Any.Type
        let columnName: String
        let sqliteType: SQLiteStorageClass
        let isPrimaryKey: Bool
        let isUnique: Bool
        let isIndexed: Bool
    }
}
