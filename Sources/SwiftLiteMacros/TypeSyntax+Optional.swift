import SwiftSyntax

extension TypeSyntax
{
    func unwrapOptional() -> (TypeSyntax, Bool)
    {
        // Case 1: Optional<T> (explicit generic syntax)
        if
            let identifierType = self.as(IdentifierTypeSyntax.self),
            identifierType.name.text == "Optional",
            let genericArguments = identifierType.genericArgumentClause?.arguments,
            let firstArgument = genericArguments.first?.argument.as(TypeSyntax.self)
        {
            return (firstArgument, true)
        }
        
        // Case 2: T? (syntactic sugar with OptionalTypeSyntax)
        if let optionalType = self.as(OptionalTypeSyntax.self) {
            return (optionalType.wrappedType, true)
        }
        
        // Case 3: ImplicitlyUnwrappedOptional<T> (explicit generic syntax)
        if
            let identifierType = self.as(IdentifierTypeSyntax.self),
            identifierType.name.text == "ImplicitlyUnwrappedOptional",
            let genericArguments = identifierType.genericArgumentClause?.arguments,
            let firstArgument = genericArguments.first?.argument.as(TypeSyntax.self)
        {
            return (firstArgument, true)
        }
        
        // Case 4: T! (syntactic sugar with ImplicitlyUnwrappedOptionalTypeSyntax)
        if let iuoType = self.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
            return (iuoType.wrappedType, true)
        }
        
        // Not an optional
        return (self, false)
    }
}
