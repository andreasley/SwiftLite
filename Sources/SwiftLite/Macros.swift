/// A macro that produces both a value and a string containing the
/// source code that generated the value. For example,
///
///     #stringify(x + y)
///
/// produces a tuple `(x + y, "x + y")`.
@freestanding(expression)
public macro stringify<T>(_ value: T) -> (T, String) = #externalMacro(module: "SwiftLiteMacros", type: "StringifyMacro")


@attached(memberAttribute)
@attached(member, names: named(id), named(_metadata), named(_editableData), named(init), named(EditableData))
@attached(extension, conformances: SwiftLite.Model, WithModelLifecycleFunctions, names: named(_beginAutoupdating), named(_hasPendingChanges), named(_beginSaving), named(_endSaving), named(_update), named(_cascadeDeletion), named(Schema), named(FallbackValues), named(DefaultValues), named(QueryProxy), named(Snapshot), arbitrary)
public macro Model(withLifecycleFunctions: Bool = false) = #externalMacro(module: "SwiftLiteMacros", type: "ModelMacro")


@attached(peer)
public macro Stored(columName: String? = nil, defaultValue: Any? = nil, fallbackValue: Any? = nil, isUnique: Bool = false, isIndexed: Bool = true) = #externalMacro(module: "SwiftLiteMacros", type: "StoredMacro")


@attached(peer)
public macro Related(onDelete: DeletionPolicy = .ignore, defaultValue: Any? = nil, fallbackValue: Any? = nil, isUnique: Bool = false) = #externalMacro(module: "SwiftLiteMacros", type: "RelatedMacro")


@attached(peer)
public macro Transient() = #externalMacro(module: "SwiftLiteMacros", type: "TransientMacro")


@attached(peer)
public macro File() = #externalMacro(module: "SwiftLiteMacros", type: "FileMacro")

@attached(peer)
public macro SnapshotCompatible() = #externalMacro(module: "SwiftLiteMacros", type: "SnapshotCompatibleMacro")

@attached(peer)
public macro SnapshotPrefetched() = #externalMacro(module: "SwiftLiteMacros", type: "SnapshotPrefetchedMacro")


@attached(accessor, names: named(get), named(set))
public macro EditableValue() = #externalMacro(module: "SwiftLiteMacros", type: "EditableValueMacro")


@attached(accessor, names: named(get))
public macro RelatedMany<T>(_ type: T.Type, onDelete: DeletionPolicy = .ignore) = #externalMacro(module: "SwiftLiteMacros", type: "RelatedManyMacro")


@attached(accessor, names: named(get))
public macro InverseRelated<T, U>(_ keyPath: KeyPath<T, U>) = #externalMacro(module: "SwiftLiteMacros", type: "InverseRelatedMacro")


@attached(accessor, names: named(get))
public macro InverseRelatedMany<T, U>(_ keyPath: KeyPath<T, U>) = #externalMacro(module: "SwiftLiteMacros", type: "InverseRelatedManyMacro")


/// Generates async loading infrastructure for a SwiftUI View with @EditableObject properties.
///
/// This macro analyzes the `@EditableObject` properties in your View and automatically generates:
/// - An `ItemsContainer` class that manages loading, saving, and lifecycle of database objects
/// - A `loading()` static method for creating the view with database object references
/// - A `PreloadView` struct that handles the async loading and displays status
/// - Conformance to the `AsyncLoadingView` protocol
///
/// ## Usage
///
/// Apply this macro to a SwiftUI View that contains `@EditableObject` properties:
///
/// ```swift
/// // Uses DefaultStatusView by default
/// @AsyncLoadingView
/// struct CarDetailView: View {
///     @EditableObject(autosaving: true) var car: Car
///     @EditableObject(autosaving: false) var engine: Engine
///
///     var body: some View {
///         // Your view implementation
///     }
/// }
///
/// // Or specify a custom StatusView
/// @AsyncLoadingView(statusView: MyCustomStatusView.self)
/// struct EngineDetailView: View {
///     @EditableObject(autosaving: true) var engine: Engine
///     // ...
/// }
/// ```
///
/// Then use the generated `loading()` method to create the view:
///
/// ```swift
/// CarDetailView.loading(
///     car: carReference,
///     engine: engineReference
/// )
/// ```
///
/// ## Requirements
///
/// - Must be applied to a `struct` that conforms to `View`
/// - Must have at least one `@EditableObject` property
/// - All `@EditableObject` properties must use types that conform to `Model`
///
/// ## Generated Code
///
/// The macro generates:
/// - `ItemsContainer`: An `@Observable` class (added to the struct) conforming to `LoadableItemsContainer`
/// - `loading()`: A static factory method (in extension) accepting `DatabaseObjectReferenceConvertible` parameters
/// - `PreloadView`: A view (in extension) that handles loading states and lifecycle
/// - Conformance to `AsyncLoadingView` protocol
///
/// - Parameters:
///   - statusView: The type of view to display loading/saving/error states. Defaults to `DefaultStatusView.self`
///
@attached(extension, conformances: AsyncLoadingView, names: arbitrary)
@attached(member, names: arbitrary)
public macro AsyncLoadingView(statusView: Any.Type = DefaultStatusView.self) = #externalMacro(
    module: "SwiftLiteMacros",
    type: "AsyncLoadingViewMacro"
)
