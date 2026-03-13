import SwiftUI

@MainActor
@propertyWrapper
public struct Loaded<T>: DynamicProperty
{
    @State public private(set) var wrappedValue: T
    
    public init(wrappedValue: T)
    {
        self.wrappedValue = wrappedValue
    }
}
