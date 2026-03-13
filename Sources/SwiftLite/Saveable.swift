public nonisolated protocol Saveable
{
    var _hasPendingChanges: Bool { get }
    func _beginSaving(transaction: DatabaseTask.WriteTransaction, changeset: Changeset) throws
    func _endSaving(success: Bool, transaction: DatabaseTask.WriteTransaction)
}

public nonisolated extension Saveable where Self: ModelSnapshot
{
    func _beginSaving(transaction: DatabaseTask.WriteTransaction, changeset: Changeset) throws {}
    func _endSaving(success: Bool, transaction: DatabaseTask.WriteTransaction) {}
}
