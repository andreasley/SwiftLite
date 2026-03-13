public nonisolated protocol AnyInverseManyToMany<T> where T: Model
{
    associatedtype T = Schema.Parent
    associatedtype Schema: RelationshipModelSchema
    associatedtype Collection: AnyInverseManyToManyCollection<T.Snapshot>
    
    var collection: Collection { get }
    @MainActor func _beginAutoupdating()
}

public nonisolated protocol AnyInverseManyToManyCollection<Element>: RandomAccessCollection where Element: ModelSnapshot
{
    associatedtype Element
//    mutating func append(_ element: Element)
//    mutating func remove(_ element: Element) -> Element?
}
