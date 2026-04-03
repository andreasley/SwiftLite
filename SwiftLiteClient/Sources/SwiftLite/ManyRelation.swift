import Foundation

public nonisolated protocol AnyInverseManyToMany<S> where S: ModelSnapshot
{
    associatedtype S
    
    var collection: RelatedCollection<S> { get }
    var _hasPendingChanges: Bool { get }

    nonisolated(nonsending) func _beginSaving(changeset: Changeset) async throws
    func _endSaving(success: Bool, transactionId: UUID)

    @MainActor func _beginAutoupdating()
}
