public nonisolated protocol AnyInverseManyToMany<T> where T: Model
{
    associatedtype T = Schema.Parent
    associatedtype Schema: RelationshipModelSchema
    
    var collection: RelatedCollection<T.Snapshot> { get }
    @MainActor func _beginAutoupdating()
}
