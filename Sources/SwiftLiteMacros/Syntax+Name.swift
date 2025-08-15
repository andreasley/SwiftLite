import SwiftSyntax

extension Syntax
{
    var name: String? {
        switch self.kind {
        case .actorDecl:
            self.as(ActorDeclSyntax.self)!.name.trimmedDescription
        case .classDecl:
            self.as(ClassDeclSyntax.self)!.name.trimmedDescription
        case .enumDecl:
            self.as(EnumDeclSyntax.self)!.name.trimmedDescription
        case .structDecl:
            self.as(StructDeclSyntax.self)!.name.trimmedDescription
        case .extensionDecl:
            self.as(ExtensionDeclSyntax.self)!.extendedType.trimmedDescription
        default:
            nil
        }
    }
}
