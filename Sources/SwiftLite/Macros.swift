/// A macro that produces both a value and a string containing the
/// source code that generated the value. For example,
///
///     #stringify(x + y)
///
/// produces a tuple `(x + y, "x + y")`.
@freestanding(expression)
public macro stringify<T>(_ value: T) -> (T, String) = #externalMacro(module: "SwiftLiteMacros", type: "StringifyMacro")

// TODO: Limit names to actually used ones
// TODO: Add parameters for table name and perhaps other table configuration (like `STRICT`)
@attached(member, names: arbitrary)
@attached(extension, conformances: SwiftLite.FetchableObject, SwiftLite.Model)
public macro Model() = #externalMacro(module: "SwiftLiteMacros", type: "ModelMacro")

@attached(peer)
public macro Unique() = #externalMacro(module: "SwiftLiteMacros", type: "UniqueMacro")

@attached(peer)
public macro Indexed(index: String? = nil) = #externalMacro(module: "SwiftLiteMacros", type: "IndexedMacro")

@attached(peer)
public macro DefaultValue<T>(_ value: T) = #externalMacro(module: "SwiftLiteMacros", type: "DefaultValueMacro")
