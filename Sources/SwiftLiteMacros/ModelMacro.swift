import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

public struct ModelMacro: MemberMacro
{
    enum ModelFixItMessage: String, FixItMessage {
        case removeDefaultValue

        var message: String {
            switch self {
            case .removeDefaultValue:
                "Remove default value."
            }
        }

        var fixItID: MessageID {
            MessageID(domain: "ModelMacro", id: self.rawValue)
        }
    }
    
    enum ErrorMessage: String, DiagnosticMessage {
        case duplicateInitializer
        case notAClass
        case propertyDefaultValue

        var message: String {
            switch self {
            case .duplicateInitializer:
                "SwiftLite Models aren't allowed to have a custom default initializer. Use convenience initializers instead."
            case .notAClass:
                "SwiftLite Model must be a class."
            case .propertyDefaultValue:
                "Properties in a SwiftLite Model must not have a default value. Annotate the property with `@Default()` or use a convenience initializer."
            }
        }
        
        var diagnosticID: MessageID {
            MessageID(domain: "ModelMacro", id: self.rawValue)
        }
        
        var severity: DiagnosticSeverity {
            .error
        }
    }

    public static func expansion(of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax, in context: some MacroExpansionContext) throws -> [DeclSyntax]
    {
        var diagnostics: [Diagnostic] = []
        var generatedDeclarations: [DeclSyntax] = []

        // MARK: Check object type
        // Check if the annotated object is a `class` (which is the only supported nominal type)

        let classDecl = declaration.as(ClassDeclSyntax.self)
        if classDecl == nil {
            diagnostics.append(Diagnostic(node: declaration, message: ErrorMessage.notAClass))
        }

        
        // MARK: Initializer
        // Check if there's already an initializer. If so, throw (because it's necessary to generate the required initializers to properly handle read-only fields and the `id` property.
        
        if let initMember = declaration.memberBlock.members.first(where: { member in
            guard let initDecl = member.decl.as(InitializerDeclSyntax.self) else { return false }
            return !initDecl.modifiers.contains(where: { $0.name.text == "convenience" })
        }) {
            let diag = Diagnostic(node: initMember.decl, message: ErrorMessage.duplicateInitializer)
            diagnostics.append(diag)
        }

        // TODO: Iterate properties
        let initDecl: DeclSyntax =
        """
        init(name: String, year: Int)
        {
            self.name = name
            self.year = year
        }
        """
        generatedDeclarations.append(initDecl)

        
        // MARK: ID

        let idDecl: DeclSyntax =
        """
        let id: UUID
        """
        generatedDeclarations.append(idDecl)

        // MARK: Fields (later: Entity)
        // TODO: Generate Entity

        var propertyNames: [String] = []
        
        for member in declaration.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            guard varDecl.bindings.count == 1, varDecl.bindings.first?.accessorBlock == nil else { continue }
            if let name = varDecl.bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier.text {
                propertyNames.append(name)
            }
            for binding in varDecl.bindings {
                if let initializer = binding.initializer {
                    // TODO: Change FixIt to move the value to a @Default() Macro instead of just deleting the initializer
                    let fixIt = FixIt(
                        message: ModelFixItMessage.removeDefaultValue,
                        changes: [
                            FixIt.Change.replace(
                                oldNode: Syntax(initializer),
                                newNode: Syntax(TokenSyntax(stringLiteral: ""))
                            )
                        ]
                    )

                    let diag = Diagnostic(node: varDecl, message: ErrorMessage.propertyDefaultValue, fixIt: fixIt)
                    diagnostics.append(diag)
                }
            }
        }

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
        generatedDeclarations.append(fieldsDecl)


        if let classDecl {

            // MARK: Table name
            let tableName = try createTableNameFromQualifiedName(of: classDecl, in: context)
            let memberDecl: DeclSyntax =
            """
            static let table = "\(raw: tableName)"
            """
            generatedDeclarations.append(memberDecl)
        }

        // MARK: Entity registration

        let entityRegistrationDecl: DeclSyntax =
        """
        private static let __schemaRegistration: Void = {
            Schema.default.register(entity)
        }()
        """
        generatedDeclarations.append(entityRegistrationDecl)

        // MARK: Throw errors if there were some

        if diagnostics.count > 0 {
            throw DiagnosticsError(diagnostics: diagnostics)
        }
        
        return generatedDeclarations
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
