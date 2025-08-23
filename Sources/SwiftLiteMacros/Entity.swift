
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
        let columnName: String
        let sqliteType: SQLiteStorageClass
        let isPrimaryKey: Bool
        let isUnique: Bool
        let isIndexed: Bool
    }
}
