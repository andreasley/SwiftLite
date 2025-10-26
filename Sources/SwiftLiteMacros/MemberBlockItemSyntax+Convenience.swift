import SwiftSyntax
import SwiftSyntaxMacros
import SwiftSyntaxBuilder

extension MemberBlockItemSyntax
{
    enum BindingSpecifier {
        case `var`
        case `let`
        
        var keyword: TokenSyntax {
            switch self {
            case .var: return .keyword(.var)
            case .let: return .keyword(.let)
            }
        }
    }
    
    init(_ specifier: BindingSpecifier, name: String, type: String)
    {
        let type = TypeSyntax(IdentifierTypeSyntax(name: .identifier("SwiftLite.Database")))
        self.init(specifier, name: name, type: type)
    }
    
    init(_ specifier: BindingSpecifier, name: String, type: TypeSyntax)
    {
        let variableDeclSyntax = VariableDeclSyntax(bindingSpecifier: specifier.keyword) {
            PatternBindingSyntax(
                pattern: IdentifierPatternSyntax(identifier: .identifier(name)),
                typeAnnotation: TypeAnnotationSyntax(colon: .colonToken(), type: type)
            )
        }
        
        self.init(decl: variableDeclSyntax)
    }
}
