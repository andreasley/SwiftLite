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
@attached(extension, conformances: SwiftLite.Model)
public macro Model(tableName: String? = nil) = #externalMacro(module: "SwiftLiteMacros", type: "ModelMacro")


@attached(peer)
public macro Stored(columName: String? = nil, defaultValue: Any? = nil, isUnique: Bool = false, isIndexed: Bool = true) = #externalMacro(module: "SwiftLiteMacros", type: "StoredMacro")

@attached(peer)
public macro Related() = #externalMacro(module: "SwiftLiteMacros", type: "RelatedMacro")

@attached(peer)
public macro Transient() = #externalMacro(module: "SwiftLiteMacros", type: "TransientMacro")

@attached(peer)
public macro File() = #externalMacro(module: "SwiftLiteMacros", type: "FileMacro")
