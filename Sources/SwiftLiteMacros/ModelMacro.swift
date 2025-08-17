import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct ModelMacro: MemberMacro
{
    enum Error: Swift.Error, CustomStringConvertible {
        case notAClass
        
        var description: String {
            switch self {
            case .notAClass:
                return "The target must be a class."
            }
        }
    }
    
    public static func expansion(of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax, in context: some MacroExpansionContext) throws -> [DeclSyntax]
    {
        var propertyNames: [String] = []
        
        for member in declaration.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            guard varDecl.bindings.count == 1, varDecl.bindings.first?.accessorBlock == nil else { continue }
            if let name = varDecl.bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier.text {
                propertyNames.append(name)
            }
        }
        
        guard let classDecl = declaration.as(ClassDeclSyntax.self) else {
            throw Error.notAClass
        }

        // MARK: id

        let idDecl: DeclSyntax =
        """
        let id: UUID = UUID()
        """


        // MARK: Fields (later: Entity)
        // TODO: Generate Entity

        let fieldsArrayExpression = ArrayExprSyntax {
            for propertyName in propertyNames {
                ArrayElementSyntax(expression: StringLiteralExprSyntax(content: propertyName))
            }
        }

        let fieldsDecl: DeclSyntax =
        """
        static let fields = \(fieldsArrayExpression)
        private static let entity = Schema.Entity(properties: [
            Schema.Entity.Property(name: "publicId", type: "UUID", isPrimaryKey: false, isUnique: true, isIndexed: false),
            Schema.Entity.Property(name: "name", type: "String", isPrimaryKey: false, isUnique: false, isIndexed: false),
            Schema.Entity.Property(name: "year", type: "Int", isPrimaryKey: false, isUnique: false, isIndexed: false),
        ])
        """

        // MARK: table name

        let tableName = try createTableNameFromQualifiedName(of: classDecl, in: context)
        let memberDecl: DeclSyntax =
        """
        static let table = "\(raw: tableName)"
        """

        // MARK: Entity registration

        let entityRegistrationDecl: DeclSyntax =
        """
        private static let __schemaRegistration: Void = {
            Schema.default.register(entity)
        }()
        """

        return [idDecl, entityRegistrationDecl, memberDecl, fieldsDecl]
    }

    static func createTableNameFromQualifiedName(of declaration: ClassDeclSyntax, in context: MacroExpansionContext) throws -> String
    {
        var components: [String] = [declaration.name.text]

        for parent in context.lexicalContext {
            guard let named = parent.asProtocol(NamedDeclSyntax.self) else { continue }
            components.insert(named.name.text, at: 0)
        }

        let sanitizedTableName = try SQLiteHelpers.generateTableName(components)
        return sanitizedTableName
    }
}
