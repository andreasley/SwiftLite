import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

public struct BackedMacro: PeerMacro, AccessorMacro
{
    public enum Error: Swift.Error, CustomStringConvertible {
        case invalidDeclaration
        
        public var description: String {
            switch self {
            case .invalidDeclaration:
                return "@Backed requires a variable with an explicit type annotation"
            }
        }
    }

    public static func expansion(of node: SwiftSyntax.AttributeSyntax, providingPeersOf declaration: some SwiftSyntax.DeclSyntaxProtocol, in context: some SwiftSyntaxMacros.MacroExpansionContext) throws -> [SwiftSyntax.DeclSyntax]
    {
        guard
            let varDecl = declaration.as(VariableDeclSyntax.self),
            let binding = varDecl.bindings.first,
            let type = binding.typeAnnotation?.type,
            let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier,
            varDecl.bindingSpecifier.tokenKind == .keyword(.var)
        else { throw Error.invalidDeclaration }

        // TODO: Check if this is early enough that `@ObservationTracking` is added (and the respective getter/setter generated) when the parent class is `@Observable`
        
        return [
            """
            private var _\(raw: identifier.text): \(type)
            """
        ]
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
        let backingName = "_\(propertyName)"

        return [
            """
            get { \(raw: backingName) }
            """,
            """
            set {
                \(raw: backingName) = newValue
                _changes.log(keyPath: \\.\(raw: propertyName), value: newValue)
            }
            """
        ]
    }
}
