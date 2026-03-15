/// A macro that produces both a value and a string containing the
/// source code that generated the value. For example,
///
///     #stringify(x + y)
///
/// produces a tuple `(x + y, "x + y")`.
@freestanding(expression)
public macro stringify<T>(_ value: T) -> (T, String) = #externalMacro(module: "SwiftLiteMacros", type: "StringifyMacro")

// TODO: Limit names to actually used ones
@attached(memberAttribute)
@attached(member, names: named(id), named(_metadata), named(_editableData), named(init))
@attached(extension, conformances: SwiftLite.Model, names: named(_beginAutoupdating), named(_hasPendingChanges), named(_beginSaving), named(_endSaving), named(_update), named(_cascadeDeletion), named(Schema), named(FallbackValues), named(DefaultValues), named(EditableData), named(QueryProxy), named(Snapshot))
public macro Model() = #externalMacro(module: "SwiftLiteMacros", type: "ModelMacro")


@attached(peer)
public macro Stored(columName: String? = nil, defaultValue: Any? = nil, isUnique: Bool = false, isIndexed: Bool = true) = #externalMacro(module: "SwiftLiteMacros", type: "StoredMacro")

@attached(peer)
public macro Related(onDelete: DeletionPolicy = .ignore) = #externalMacro(module: "SwiftLiteMacros", type: "RelatedMacro")

@attached(peer)
public macro Transient() = #externalMacro(module: "SwiftLiteMacros", type: "TransientMacro")

@attached(peer)
public macro File() = #externalMacro(module: "SwiftLiteMacros", type: "FileMacro")

@attached(accessor, names: named(get), named(set))
public macro EditableValue() = #externalMacro(module: "SwiftLiteMacros", type: "EditableValueMacro")



@attached(accessor, names: named(get))
public macro RelatedMany<T>(_ type: T.Type, onDelete: DeletionPolicy = .ignore) = #externalMacro(module: "SwiftLiteMacros", type: "RelatedManyMacro")

@attached(accessor, names: named(get))
public macro InverseRelated<T, U>(_ keyPath: KeyPath<T, U>) = #externalMacro(module: "SwiftLiteMacros", type: "InverseRelatedMacro")

@attached(accessor, names: named(get))
public macro InverseRelatedMany<T, U>(_ keyPath: KeyPath<T, U>) = #externalMacro(module: "SwiftLiteMacros", type: "InverseRelatedManyMacro")


