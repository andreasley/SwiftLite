import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

public struct RelatedManyMacro: AccessorMacro, PeerMacro
{
    public enum DiagnosticMessage: String, SwiftDiagnostics.DiagnosticMessage {
        case invalidDeclaration
        case missingTypeArgument
        case wrongTypeAnnotation
        
        public var message: String {
            switch self {
            case .invalidDeclaration:
                return "@RelatedMany requires a variable declaration"
            case .missingTypeArgument:
                return "@RelatedMany requires a type argument (e.g., @RelatedMany(Passenger.self))"
            case .wrongTypeAnnotation:
                return "Type annotation must match expected collection type"
            }
        }
        
        public var diagnosticID: MessageID {
            MessageID(domain: "RelatedManyMacro", id: rawValue)
        }
        
        public var severity: DiagnosticSeverity {
            .error
        }
    }
    
    public enum Error: Swift.Error, CustomStringConvertible {
        case invalidDeclaration
        case missingTypeArgument
        
        public var description: String {
            switch self {
            case .invalidDeclaration:
                return "@RelatedMany requires a variable declaration"
            case .missingTypeArgument:
                return "@RelatedMany requires a type argument (e.g., @RelatedMany(Passenger.self))"
            }
        }
    }
    
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax]
    {
        guard
            let varDecl = declaration.as(VariableDeclSyntax.self),
            let binding = varDecl.bindings.first,
            let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier
        else { throw Error.invalidDeclaration }

        let propertyName = identifier.text
        
        // Extract the type argument from @RelatedMany(Passenger.self)
        var relatedTypeName: String = "Unknown"
        if case .argumentList(let arguments) = node.arguments,
           let firstArg = arguments.first {
            // Try to extract the type from expressions like "Passenger.self"
            if let memberAccess = firstArg.expression.as(MemberAccessExprSyntax.self),
               let baseType = memberAccess.base?.as(DeclReferenceExprSyntax.self) {
                relatedTypeName = baseType.baseName.text
            }
        }
        
        // Generate the relation schema name: PassengersRelationSchema
        let schemaName = propertyName.prefix(1).uppercased() + propertyName.dropFirst() + "RelationSchema"
        
        // Generate the collection type name: PassengersCollection
        let collectionTypeName = propertyName.prefix(1).uppercased() + propertyName.dropFirst() + "Collection"
        
        // Generate typealias
        let typealiasDecl: DeclSyntax =
        """
        typealias \(raw: collectionTypeName) = ManyToMany<\(raw: schemaName)>.Collection
        """
        
        return [typealiasDecl]
    }
    
    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax]
    {
        guard
            let varDecl = declaration.as(VariableDeclSyntax.self),
            let binding = varDecl.bindings.first,
            let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier,
            varDecl.bindingSpecifier.tokenKind == .keyword(.var)
        else { throw Error.invalidDeclaration }

        let propertyName = identifier.text
        
        // Generate the expected collection type name
        let expectedTypeName = propertyName.prefix(1).uppercased() + propertyName.dropFirst() + "Collection"
        
        // Check if type annotation exists and matches expected
        if let typeAnnotation = binding.typeAnnotation {
            let actualTypeName = typeAnnotation.type.trimmedDescription
            if actualTypeName != expectedTypeName {
                // Type annotation exists but is wrong - provide Fix-It to replace it
                let fixIt = FixIt(
                    message: MacroExpansionFixItMessage("Change to '\(expectedTypeName)'"),
                    changes: [
                        .replace(
                            oldNode: Syntax(typeAnnotation.type),
                            newNode: Syntax(IdentifierTypeSyntax(name: .identifier(expectedTypeName)))
                        )
                    ]
                )
                
                let diagnostic = Diagnostic(
                    node: typeAnnotation.type,
                    message: DiagnosticMessage.wrongTypeAnnotation,
                    fixIt: fixIt
                )
                context.diagnose(diagnostic)
            }
        } else {
            // Type annotation is missing - provide Fix-It to add it
            let newTypeAnnotation = TypeAnnotationSyntax(
                colon: .colonToken(trailingTrivia: .space),
                type: IdentifierTypeSyntax(name: .identifier(expectedTypeName))
            )
            
            let fixIt = FixIt(
                message: MacroExpansionFixItMessage("Add type annotation ': \(expectedTypeName)'"),
                changes: [
                    .replace(
                        oldNode: Syntax(binding),
                        newNode: Syntax(
                            binding.with(\.typeAnnotation, newTypeAnnotation)
                        )
                    )
                ]
            )
            
            let diagnostic = Diagnostic(
                node: binding,
                message: DiagnosticMessage.wrongTypeAnnotation,
                fixIt: fixIt
            )
            context.diagnose(diagnostic)
        }

        return [
            """
            get { _editableData.\(raw: propertyName).collection }
            """,
            """
            set { _editableData.\(raw: propertyName).collection = newValue }
            """
        ]
    }
}
