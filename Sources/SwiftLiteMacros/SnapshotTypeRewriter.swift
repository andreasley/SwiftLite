import SwiftSyntax

final class SnapshotTypeRewriter: SyntaxRewriter
{
    override func visit(_ node: IdentifierTypeSyntax) -> TypeSyntax
    {
        let modified = IdentifierTypeSyntax(
            name: node.name,
            genericArgumentClause: node.genericArgumentClause
        )

        let memberType = MemberTypeSyntax(
            baseType: TypeSyntax(modified),
            period: .periodToken(),
            name: .identifier("Snapshot")
        )

        return TypeSyntax(memberType)
    }
}
