import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

public struct StoredMacro: PeerMacro
{
    enum StoredDiagnostic: String, DiagnosticMessage {
        case hasDefaultValue
        
        var severity: DiagnosticSeverity {
            switch self {
            case .hasDefaultValue:
                return .error
            }
        }
        
        var message: String {
            switch self {
            case .hasDefaultValue:
                return "@Stored properties cannot have default values; use the 'defaultValue' parameter instead"
            }
        }
        
        var diagnosticID: MessageID {
            MessageID(domain: "SwiftLite", id: rawValue)
        }
    }
    
    public static func expansion(of node: SwiftSyntax.AttributeSyntax, providingPeersOf declaration: some SwiftSyntax.DeclSyntaxProtocol, in context: some SwiftSyntaxMacros.MacroExpansionContext) throws -> [SwiftSyntax.DeclSyntax] {
        
        // Check if this is a variable declaration with an initializer
        guard let varDecl = declaration.as(VariableDeclSyntax.self) else {
            return []
        }
        
        // Check if any binding has an initializer
        for binding in varDecl.bindings {
            if let initializer = binding.initializer {
                // Extract the default value expression
                let defaultValueExpr = initializer.value
                
                // Check if the @Stored attribute already has a defaultValue parameter
                let hasDefaultValueParam = hasDefaultValueParameter(in: node)
                
                if !hasDefaultValueParam {
                    // Create Fix-It to move the default value to the annotation
                    let fixIt = createFixIt(
                        attribute: node,
                        initializer: initializer,
                        defaultValueExpr: defaultValueExpr,
                        binding: binding
                    )
                    
                    let diagnostic = Diagnostic(
                        node: Syntax(initializer),
                        message: StoredDiagnostic.hasDefaultValue,
                        fixIts: [fixIt]
                    )
                    context.diagnose(diagnostic)
                }
            }
        }
        
        return []
    }
    
    private static func hasDefaultValueParameter(in attribute: AttributeSyntax) -> Bool {
        guard let arguments = attribute.arguments,
              case .argumentList(let labeledArgs) = arguments else {
            return false
        }
        
        for arg in labeledArgs {
            if arg.label?.text == "defaultValue" {
                return true
            }
        }
        return false
    }
    
    private static func createFixIt(
        attribute: AttributeSyntax,
        initializer: InitializerClauseSyntax,
        defaultValueExpr: ExprSyntax,
        binding: PatternBindingSyntax
    ) -> FixIt {
        // Build the new attribute with the defaultValue parameter
        let newAttribute = buildUpdatedAttribute(
            original: attribute,
            defaultValue: defaultValueExpr
        )
        
        // Build the new binding without the initializer
        let newBinding = binding.with(\.initializer, nil)
        
        return FixIt(
            message: MacroExpansionFixItMessage("Move default value to '@Stored(defaultValue:)' parameter"),
            changes: [
                .replace(
                    oldNode: Syntax(attribute),
                    newNode: Syntax(newAttribute)
                ),
                .replace(
                    oldNode: Syntax(binding),
                    newNode: Syntax(newBinding)
                )
            ]
        )
    }
    
    private static func buildUpdatedAttribute(
        original: AttributeSyntax,
        defaultValue: ExprSyntax
    ) -> AttributeSyntax {
        // Get existing arguments or create new list
        var newArguments: [LabeledExprSyntax] = []
        
        if let arguments = original.arguments,
           case .argumentList(let labeledArgs) = arguments {
            newArguments = Array(labeledArgs)
        }
        
        // Add the defaultValue parameter
        let defaultValueArg = LabeledExprSyntax(
            label: "defaultValue",
            colon: .colonToken(trailingTrivia: .space),
            expression: defaultValue,
            trailingComma: nil
        )
        
        // Add comma to previous last argument if needed
        if !newArguments.isEmpty {
            let lastIndex = newArguments.count - 1
            newArguments[lastIndex] = newArguments[lastIndex].with(\.trailingComma, .commaToken(trailingTrivia: .space))
        }
        
        newArguments.append(defaultValueArg)
        
        // Build new attribute arguments with proper parentheses
        let newLabeledArgs = LabeledExprListSyntax(newArguments)
        
        // Create updated attribute with parenthesized argument list
        var newAttribute = original.with(
            \.arguments,
            .argumentList(newLabeledArgs)
        )
        
        // Ensure parentheses are present (needed when original had no arguments)
        if original.leftParen == nil {
            newAttribute = newAttribute
                .with(\.leftParen, .leftParenToken())
                .with(\.rightParen, .rightParenToken())
        }
        
        return newAttribute
    }
}

