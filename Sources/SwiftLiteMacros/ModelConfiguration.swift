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
        var defaultValueInitializer: InitializerClauseSyntax? {
            return if let defaultValuePropertyName {
                InitializerClauseSyntax(value: ExprSyntax(stringLiteral: defaultValuePropertyName))
            } else if typeIsOptional {
                InitializerClauseSyntax(value: ExprSyntax("nil"))
            } else {
                nil
            }
        }
        
        let name: String
        let columnName: ExprSyntax
        let type: TypeSyntax
        let unwrappedType: TypeSyntax
        let typeIsOptional: Bool
        let positionInPrimaryKey: Int?
        let isUnique: Bool
        let isIndexed: Bool
        let isRelated: Bool
        let defaultValue: ExprSyntax?
        let defaultValuePropertyName: String?
        
        init(name: String, columnName: ExprSyntax, type: TypeSyntax, positionInPrimaryKey: Int? = nil, isUnique: Bool = false, isIndexed: Bool = false, isRelated: Bool = false, defaultValue: ExprSyntax? = nil, defaultValuePropertyName: String? = nil)
        {
            (self.unwrappedType, self.typeIsOptional) = type.unwrapOptional()

            self.name = name
            self.type = type
            self.columnName = columnName
            self.positionInPrimaryKey = positionInPrimaryKey
            self.isUnique = isUnique
            self.isIndexed = isIndexed
            self.isRelated = isRelated
            self.defaultValue = defaultValue
            self.defaultValuePropertyName = defaultValuePropertyName
        }
    }
}
