import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct SwiftLitePlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        ModelMacro.self,
        StoredMacro.self,
        RelatedMacro.self,
        RelatedManyMacro.self,
        FileMacro.self,
        TransientMacro.self,
        SnapshotCompatibleMacro.self,
        SnapshotPrefetchedMacro.self,
        EditableValueMacro.self,
        InverseRelatedMacro.self,
        InverseRelatedManyMacro.self,
        AsyncLoadingViewMacro.self,
    ]
}
