import Foundation

public nonisolated protocol AnyInverseManyToMany<S> where S: ModelSnapshot
{
    associatedtype S
    
    var collection: RelatedCollection<S> { get }
    var _hasPendingChanges: Bool { get }

    func _beginSaving(changeset: Changeset) throws
    func _endSaving(success: Bool, transactionId: UUID)

    @MainActor func _beginAutoupdating()
}
