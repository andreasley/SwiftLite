import Foundation

public nonisolated protocol Saveable
{
    var _hasPendingChanges: Bool { get }
    func _beginSaving(changeset: Changeset) throws
    func _endSaving(success: Bool, transactionId: UUID)
}

public nonisolated extension Saveable where Self: ModelSnapshot
{
    func _beginSaving(changeset: Changeset) throws {}
    func _endSaving(success: Bool, transactionId: UUID) {}
}
