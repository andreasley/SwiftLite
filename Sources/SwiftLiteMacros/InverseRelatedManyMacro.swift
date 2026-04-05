import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

public struct InverseRelatedManyMacro: AccessorMacro
{
    public enum DiagnosticMessage: String, SwiftDiagnostics.DiagnosticMessage {
        case invalidDeclaration
        case missingKeyPath
        case invalidKeyPath
        case wrongTypeAnnotation
        
        public var message: String {
            switch self {
            case .invalidDeclaration:
                return "@InverseRelatedMany requires a variable declaration"
            case .missingKeyPath:
                return "@InverseRelatedMany requires a key path argument"
            case .invalidKeyPath:
                return "@InverseRelatedMany requires a valid key path in the format \\Type.property"
            case .wrongTypeAnnotation:
                return "Type annotation must match expected collection type"
            }
        }
        
        public var diagnosticID: MessageID {
            MessageID(domain: "InverseRelatedManyMacro", id: rawValue)
        }
        
        public var severity: DiagnosticSeverity {
            .error
        }
    }
    
    public enum Error: Swift.Error, CustomStringConvertible {
        case invalidDeclaration
        case missingKeyPath
        case invalidKeyPath
        
        public var description: String {
            switch self {
            case .invalidDeclaration:
                return "@InverseRelatedMany requires a variable declaration"
            case .missingKeyPath:
                return "@InverseRelatedMany requires a key path argument"
            case .invalidKeyPath:
                return "@InverseRelatedMany requires a valid key path in the format \\Type.property"
            }
        }
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
        
        // Extract the key path argument from the macro
        guard case .argumentList(let arguments) = node.arguments,
              let firstArg = arguments.first,
              let keyPathExpr = firstArg.expression.as(KeyPathExprSyntax.self)
        else { throw Error.missingKeyPath }
        
        // Extract the referenced type from the key path
        guard let rootType = keyPathExpr.root?.as(IdentifierTypeSyntax.self)?.name.text
        else { throw Error.invalidKeyPath }
        
        // Extract the property name from the key path components
        var referencingField: String?
        for component in keyPathExpr.components {
            if let propertyComponent = component.component.as(KeyPathPropertyComponentSyntax.self) {
                referencingField = propertyComponent.declName.baseName.text
                break
            }
        }
        
        guard referencingField != nil else { throw Error.invalidKeyPath }
        
        // Generate the expected collection type: RelatedCollection<RootType.Snapshot>
        let expectedTypeName = "RelatedCollection<\(rootType).Snapshot>"
        
        // Check if type annotation exists and matches expected
        if let typeAnnotation = binding.typeAnnotation {
            let actualTypeName = typeAnnotation.type.trimmedDescription
            if actualTypeName != expectedTypeName {
                // Type annotation exists but is wrong - provide Fix-It to replace it
                let snapshotType = MemberTypeSyntax(
                    baseType: IdentifierTypeSyntax(name: .identifier(rootType)),
                    period: .periodToken(),
                    name: .identifier("Snapshot")
                )
                let fixIt = FixIt(
                    message: MacroExpansionFixItMessage("Change to '\(expectedTypeName)'"),
                    changes: [
                        .replace(
                            oldNode: Syntax(typeAnnotation.type),
                            newNode: Syntax(
                                IdentifierTypeSyntax(
                                    name: .identifier("RelatedCollection"),
                                    genericArgumentClause: GenericArgumentClauseSyntax {
                                        GenericArgumentSyntax(argument: .type(TypeSyntax(snapshotType)))
                                    }
                                )
                            )
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
                type: IdentifierTypeSyntax(
                    name: .identifier("RelatedCollection"),
                    genericArgumentClause: GenericArgumentClauseSyntax {
                        GenericArgumentSyntax(argument: .type(TypeSyntax(IdentifierTypeSyntax(name: .identifier(rootType)))))
                    }
                )
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
            """
        ]
    }
}
