import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct IndexedMacro: PeerMacro
{
    public static func expansion(of node: SwiftSyntax.AttributeSyntax, providingPeersOf declaration: some SwiftSyntax.DeclSyntaxProtocol, in context: some SwiftSyntaxMacros.MacroExpansionContext) throws -> [SwiftSyntax.DeclSyntax]
    {
        []
    }
}
