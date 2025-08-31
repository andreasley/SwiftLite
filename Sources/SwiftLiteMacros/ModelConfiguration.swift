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
            return if let defaultValue {
                InitializerClauseSyntax(value: defaultValue)
            } else if typeIsOptional {
                InitializerClauseSyntax(value: ExprSyntax("nil"))
            } else {
                nil
            }
        }
        
        let name: String
        let columnName: String
        let type: TypeSyntax
        let unwrappedType: TypeSyntax
        let typeIsOptional: Bool
        let isPrimaryKey: Bool
        let isUnique: Bool
        let isIndexed: Bool
        let defaultValue: ExprSyntax?
        
        init(name: String, columnName: String, type: TypeSyntax, isPrimaryKey: Bool = false, isUnique: Bool = false, isIndexed: Bool = false, defaultValue: ExprSyntax? = nil)
        {
            (self.unwrappedType, self.typeIsOptional) = type.unwrapOptional()

            self.name = name
            self.type = type
            self.columnName = columnName
            self.isPrimaryKey = isPrimaryKey
            self.isUnique = isUnique
            self.isIndexed = isIndexed
            self.defaultValue = defaultValue
        }
    }
}
