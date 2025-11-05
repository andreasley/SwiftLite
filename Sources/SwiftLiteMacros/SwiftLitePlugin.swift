import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct SwiftLitePlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        StringifyMacro.self,
        ModelMacro.self,
        StoredMacro.self,
        RelatedMacro.self,
        FileMacro.self,
        TransientMacro.self,
        BackedMacro.self,
    ]
}
