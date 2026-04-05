import Foundation

public protocol UnqualifiedObjectReference<Model>
{
    associatedtype Model: SwiftLite.Model
    var id: Model.ID { get }
}

public nonisolated extension UnqualifiedObjectReference
{
    static func global(id: Model.ID) -> any UnqualifiedObjectReference<Model>
    {
        GlobalObjectReference(id: id)
    }
}
