import SwiftSyntax

extension ExprSyntax
{
    var boolLiteral: Bool? {
        guard let boolLiteralSyntax = self.as(BooleanLiteralExprSyntax.self) else { return nil }

        switch boolLiteralSyntax.literal.tokenKind {
            case .keyword(.true):  return true
            case .keyword(.false): return false
            default: return nil
        }
    }
}

