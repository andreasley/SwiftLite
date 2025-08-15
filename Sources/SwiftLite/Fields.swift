@attached(member, names: arbitrary) // TODO: Limit names to actually used ones
public macro Model() = #externalMacro(module: "SwiftLiteMacros", type: "ModelMacro")
