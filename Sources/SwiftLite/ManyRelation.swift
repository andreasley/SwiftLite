public nonisolated protocol AnyInverseManyToMany<T> where T: Model
{
    associatedtype T = Schema.Parent
    associatedtype Schema: RelationshipModelSchema
    
    var collection: RelatedCollection<T.Snapshot> { get }
    var _hasPendingChanges: Bool { get }

    func _beginSaving(transaction: DatabaseTask.WriteTransaction, changeset: Changeset) throws
    func _endSaving(success: Bool, transaction: DatabaseTask.WriteTransaction)

    @MainActor func _beginAutoupdating()
}
