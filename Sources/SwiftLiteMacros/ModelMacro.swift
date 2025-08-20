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
        case unexpectedPropertyDefaultValue
        case failedToGenerateTableName

        var message: String {
            switch self {
            case .duplicateInitializer:
                "SwiftLite Models aren't allowed to have a custom default initializer. Use convenience initializers instead."
            case .notAClass:
                "SwiftLite Model must be a class."
            case .unexpectedPropertyDefaultValue:
                "Properties in a SwiftLite Model must not have a default value. Annotate the property with `@Default()` or use a convenience initializer."
            case .failedToGenerateTableName:
                "Failed to generate table name from class name."
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
        
        // MARK: Generate table name

        var tableName: String?
        if let classDecl {
            // TODO: Check if there's already a `static let tableName: String`. If so, that should be used instead of a generated one.
            do {
                tableName = try createTableNameFromQualifiedName(of: classDecl, in: context)
            } catch {
                diagnostics.append(Diagnostic(node: declaration, message: ErrorMessage.failedToGenerateTableName))
                // TODO: Add FixIt to add manual table name.
            }
        }

        // MARK: Table name
        if let tableName {
            let memberDecl: DeclSyntax =
            """
            static let tableName = "\(raw: tableName)"
            """
            generatedDeclarations.append(memberDecl)
        }

        
        // MARK: ID

        let idDecl: DeclSyntax =
        """
        let id: UUID
        """
        generatedDeclarations.append(idDecl)


        // MARK: Initializer
        
        // TODO: Iterate properties only once
        // TOOD: Add default values for properties annotated with `@Default()`
        
        // Check if there's already an initializer. If so, throw (because it's necessary to generate the required initializers to properly handle read-only fields and the `id` property.
        if let initMember = declaration.memberBlock.members.first(where: { member in
            guard let initDecl = member.decl.as(InitializerDeclSyntax.self) else { return false }
            return !initDecl.modifiers.contains(where: { $0.name.text == "convenience" })
        }) {
            let diag = Diagnostic(node: initMember.decl, message: ErrorMessage.duplicateInitializer)
            diagnostics.append(diag)
        }

        // Generate initializer
        let parameters: [FunctionParameterSyntax] = declaration.memberBlock.members.compactMap { member in
            guard let variable = member.decl.as(VariableDeclSyntax.self),
                  let binding = variable.bindings.first,
                  let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else {
                return nil
            }
            
            let name = identifier.identifier.text
            let type = binding.typeAnnotation?.type.description.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Any"
            let isOptional = type.hasSuffix("?")
            
            return FunctionParameterSyntax(
                firstName: .identifier(name),
                colon: .colonToken(trailingTrivia: .space),
                type: TypeSyntax(stringLiteral: type),
                defaultValue: isOptional ? InitializerClauseSyntax(value: ExprSyntax("nil")) : nil
            )
        }
        
        let parameterList = FunctionParameterClauseSyntax { parameters }
        
        let idAssignment = CodeBlockItemSyntax(item: .expr("self.id = UUID()"))
        var assignments: [CodeBlockItemSyntax] = [idAssignment]

        for parameter in parameters {
            let name = parameter.firstName.text
            let assignment = CodeBlockItemSyntax(item: .expr("self.\(raw: name) = \(raw: name)"))
            assignments.append(assignment)
        }
        
        let initDecl = InitializerDeclSyntax(
            modifiers: [DeclModifierSyntax(name: .keyword(.public))],
            signature: FunctionSignatureSyntax(parameterClause: parameterList),
            body: CodeBlockSyntax(statements: CodeBlockItemListSyntax(assignments))
        )
        
        generatedDeclarations.append(DeclSyntax(initDecl))
        

        // MARK: Entity
        // The entity details are required in the compiled app to check the schema and execute migrations if necessary.

        var propertyNames: [String] = []
        
        for member in declaration.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            guard varDecl.bindings.count == 1, varDecl.bindings.first?.accessorBlock == nil else { continue }
            if let name = varDecl.bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier.text {
                propertyNames.append(name)
            }
            for binding in varDecl.bindings {
                // Initial values for properties aren't supported in SwiftLite, because they make it impossible to set the value for `let` properties in the initializer (which is what is required when initializing a model from database results)
                // Check if the binding has an initializer and show an error if so, because default initializers aren't supported in SwiftLite
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

                    let diag = Diagnostic(node: varDecl, message: ErrorMessage.unexpectedPropertyDefaultValue, fixIt: fixIt)
                    diagnostics.append(diag)
                }
            }
        }

        let fieldsArrayExpression = ArrayExprSyntax {
            for propertyName in propertyNames {
                ArrayElementSyntax(expression: StringLiteralExprSyntax(content: propertyName))
            }
        }

        if let classDecl {
            let entityDecl: DeclSyntax =
            """
            private static let entity = Schema.Entity<\(classDecl.name)>(properties: [
                .init(name: "id", type: "UUID", isPrimaryKey: true, isUnique: false, isIndexed: false),
                .init(name: "publicId", type: "UUID", isPrimaryKey: false, isUnique: true, isIndexed: false),
                .init(name: "name", type: "String", isPrimaryKey: false, isUnique: false, isIndexed: false),
                .init(name: "year", type: "Int", isPrimaryKey: false, isUnique: false, isIndexed: false),
            ])
            """
            generatedDeclarations.append(entityDecl)
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

        let sanitizedTableName = try SQLiteHelpers.generateIdentifierName(components)
        return sanitizedTableName
    }
}
