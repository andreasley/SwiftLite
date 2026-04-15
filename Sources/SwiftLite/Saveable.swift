import Foundation

public protocol Saveable
{
    var _hasPendingChanges: Bool { get }
    nonisolated(nonsending) func _beginSaving(changeset: Changeset) async throws
    func _endSaving(success: Bool, transactionId: UUID)
}

public extension Saveable where Self: ModelSnapshot
{
    nonisolated(nonsending) func _beginSaving(changeset: Changeset) async throws {}
    func _endSaving(success: Bool, transactionId: UUID) {}
}
