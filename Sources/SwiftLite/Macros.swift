/// A macro that produces both a value and a string containing the
/// source code that generated the value. For example,
///
///     #stringify(x + y)
///
/// produces a tuple `(x + y, "x + y")`.
@freestanding(expression)
public macro stringify<T>(_ value: T) -> (T, String) = #externalMacro(module: "SwiftLiteMacros", type: "StringifyMacro")

@attached(member, names: arbitrary) // TODO: Limit names to actually used ones
//@attached(extension, conformances: Obervable)
public macro Model(schema: Schema = .default) = #externalMacro(module: "SwiftLiteMacros", type: "ModelMacro")

@attached(peer)
public macro Unique() = #externalMacro(module: "SwiftLiteMacros", type: "UniqueMacro")

@attached(peer)
public macro Indexed(index: String? = nil) = #externalMacro(module: "SwiftLiteMacros", type: "IndexedMacro")
