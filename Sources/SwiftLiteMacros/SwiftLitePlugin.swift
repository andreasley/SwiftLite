import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct SwiftLitePlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        StringifyMacro.self,
        ModelMacro.self,
        UniqueMacro.self,
        IndexedMacro.self,
        DefaultValueMacro.self,
    ]
}
