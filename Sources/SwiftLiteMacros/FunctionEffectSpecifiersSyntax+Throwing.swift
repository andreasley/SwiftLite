import SwiftSyntax

extension FunctionEffectSpecifiersSyntax
{
    static var throwing: Self {
        return .init(throwsClause: .init(throwsSpecifier: .keyword(.throws, leadingTrivia: .spaces(1))))
    }
}
