#if canImport(SwiftUI)
import SwiftUI

@MainActor
@propertyWrapper
public struct EditableObject<T: Model>: DynamicProperty
{
    @State public private(set) var wrappedValue: T
    
    private let autosaving: Bool
    private let delayBeforeSaving: Duration

    public var projectedValue: Loaded {
        Loaded(model: wrappedValue)
    }
    
    public init(autosaving: Bool = true, delayBeforeSaving: Duration = .seconds(3))
    {
        fatalError("This initializer to \(Self.self) is not meant to be called; just a placeholder for the compiler to accept the property declaration (from where these parameters are copied to the macro-generated intermediate view")
    }

    public init(wrappedValue: T, autosaving: Bool = true, delayBeforeSaving: Duration = .seconds(3))
    {
        self.wrappedValue = wrappedValue
        self.autosaving = autosaving
        self.delayBeforeSaving = delayBeforeSaving

        if autosaving {
            wrappedValue._beginAutosaving(delayBeforeSaving: delayBeforeSaving)
        }
    }
    
    @MainActor
    @dynamicMemberLookup
    public struct Loaded
    {
        let model: T

        public subscript<Value>(dynamicMember keyPath: ReferenceWritableKeyPath<T, Value>) -> Binding<Value> where Value: Equatable {
            Binding(
                get: {
                    return model[keyPath: keyPath]
                },
                set: { newValue in
                    let oldValue = model[keyPath: keyPath]
                    guard oldValue != newValue else { return }
                    model[keyPath: keyPath] = newValue
                }
            )
        }
    }
}
#endif
