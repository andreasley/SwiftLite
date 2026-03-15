public nonisolated protocol AnyInverseManyToMany<S> where S: ModelSnapshot
{
    associatedtype S
    
    var collection: RelatedCollection<S> { get }
    var _hasPendingChanges: Bool { get }

    func _beginSaving(transaction: DatabaseTask.WriteTransaction, changeset: Changeset) throws
    func _endSaving(success: Bool, transaction: DatabaseTask.WriteTransaction)

    @MainActor func _beginAutoupdating()
}
