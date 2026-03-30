import SwiftUI

/// A protocol that marks SwiftUI Views as supporting async loading infrastructure.
///
/// This protocol is automatically conformed to by views annotated with `@AsyncLoadingView`.
/// It serves as a marker protocol to identify views that have been enhanced with
/// async loading capabilities for `@EditableObject` properties.
///
/// You typically don't conform to this protocol manually. Instead, apply the
/// `@AsyncLoadingView` macro to your view:
///
/// ```swift
/// @AsyncLoadingView
/// struct MyView: View {
///     @EditableObject(autosaving: true) var item: MyModel
///     var body: some View {
///         // ...
///     }
/// }
/// ```
@MainActor
public protocol AsyncLoadingView: View
{
    associatedtype PreloadView: View
}
