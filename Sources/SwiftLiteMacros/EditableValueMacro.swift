import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

public struct EditableValueMacro: AccessorMacro
{
    public enum Error: Swift.Error, CustomStringConvertible {
        case invalidDeclaration
        
        public var description: String {
            switch self {
            case .invalidDeclaration:
                return "@EditableValue requires a variable with an explicit type annotation"
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

        return [
            """
            get { _editableData.\(raw: propertyName) }
            """,
            """
            set {
                guard _editableData.\(raw: propertyName) != newValue else { return }
                _editableData.\(raw: propertyName) = newValue
                _metadata.logValueChange(field: "\(raw: propertyName)", value: newValue)
            }
            """
        ]
    }
}
