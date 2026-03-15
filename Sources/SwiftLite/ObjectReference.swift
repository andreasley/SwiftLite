import Foundation

public protocol ObjectReference<Model>
{
    associatedtype Model: SwiftLite.Model
    var id: Model.ID { get }
}

public nonisolated extension ObjectReference
{
    static func global(id: Model.ID) -> any ObjectReference<Model>
    {
        GlobalObjectReference(id: id)
    }
}
