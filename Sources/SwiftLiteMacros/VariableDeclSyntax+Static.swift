import SwiftSyntax

extension VariableDeclSyntax
{
    var isStatic: Bool {
        self.modifiers.contains(where: { $0.name.tokenKind == .keyword(.static) })
    }
}
