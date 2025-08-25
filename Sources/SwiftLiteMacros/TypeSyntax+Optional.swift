import SwiftSyntax

extension TypeSyntax
{
    func unwrapOptional() -> (TypeSyntax, Bool)
    {
        if let optional = self.as(OptionalTypeSyntax.self) {
            return (optional.wrappedType, true)
        } else if let simple = self.as(IdentifierTypeSyntax.self), simple.name.text == "Optional", let arg = simple.genericArgumentClause?.arguments.first {
            return (arg.argument, true)
        }
        return (self, false)
    }
}
