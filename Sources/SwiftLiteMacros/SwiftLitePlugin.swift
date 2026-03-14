import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct SwiftLitePlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        StringifyMacro.self,
        ModelMacro.self,
        StoredMacro.self,
        RelatedMacro.self,
        RelatedManyMacro.self,
        FileMacro.self,
        TransientMacro.self,
        EditableValueMacro.self,
        InverseRelatedMacro.self,
        InverseRelatedManyMacro.self,
    ]
}
