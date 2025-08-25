import SwiftSyntax

public struct ModelConfiguration: Sendable
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
        let type: TypeSyntax
        let typeIsOptional: Bool
        let isPrimaryKey: Bool
        let isUnique: Bool
        let isIndexed: Bool
        let defaultValue: ExprSyntax?
        
        init(name: String, columnName: String, type: TypeSyntax, isPrimaryKey: Bool, isUnique: Bool, isIndexed: Bool, defaultValue: ExprSyntax?)
        {
            (self.type, self.typeIsOptional) = type.unwrapOptional()

            self.name = name
            self.columnName = columnName
            self.isPrimaryKey = isPrimaryKey
            self.isUnique = isUnique
            self.isIndexed = isIndexed
            self.defaultValue = defaultValue
        }
    }
}
