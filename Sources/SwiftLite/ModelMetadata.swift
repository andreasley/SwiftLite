import Foundation

@Observable
public nonisolated final class ModelMetadata: DatabaseEntityMetadata, WithTrackedChanges
{
    public enum ObjectStatus {
        case new // not stored in database yet
        case stored
        case markedForDeletion // marked for deletion but not saved yet
        case deleted // removed from the database (but object may still exist)
        
        var hasChanges: Bool {
            switch self {
            case .new, .markedForDeletion:
                return true
            case .stored, .deleted:
                return false
            }
        }
    }
    
    public let db: Database
    public let table: String
    public let id: UUID
    
    let changedValues = UpdatedValues()
    public var objectStatus: ObjectStatus
    
    @ObservationIgnored
    var isAutosaving: Bool

    public var lastRead: Date?
    var lastWrite: Date? = nil
    var lastSavingTransactionId: UUID? = nil
    var currentSavingTransaction: DatabaseTask.WriteTransaction? = nil
    
    @ObservationIgnored
    var objectChangedNotificationToken: DeregisteringNotificationToken?
    
    var autosaveTask: Task<Void, Never>? = nil
    
    public var _hasPendingChanges: Bool {
        changedValues.hasChanges || objectStatus.hasChanges
    }
    
    public init(db: Database, table: String, id: UUID, isNew: Bool, isAutosaving: Bool = false)
    {
        self.db = db
        self.table = table
        self.id = id
        self.objectStatus = isNew ? .new : .stored
        self.isAutosaving = isAutosaving
        self.lastRead = isNew ? nil : .now
    }
    
    public func logValueChange<V: SQLValueConvertible>(field: String, value: V)
    {
        changedValues.log(field: field, value: value)
    }
    
    func hasNoPendingChange(for field: String) -> Bool
    {
        !changedValues.hasChange(for: field)
    }
    
    private func collectForSaving(transactionId: UUID) throws -> ChangedObject?
    {
        let changes = try changedValues.getChangeset()
        
        let status: ChangedObject.Status
        switch objectStatus {
            case .markedForDeletion:
            status = .deleted
        case .new:
            status = .created
        default:
            guard changes != nil else { return nil }
            status = .updated
        }
        
        return ChangedObject(table: table, objectId: id, status: status, updatedFields: changes, transactionId: transactionId)
    }
    
    public func _beginSaving(transaction: DatabaseTask.WriteTransaction, changeset: Changeset) throws
    {
        guard transaction.db == self.db else { throw ModelSavingError.wrongDatabase }

        guard currentSavingTransaction == nil else { throw ModelSavingError.alreadySaving }
        currentSavingTransaction = transaction
        try changeset.append(collectForSaving(transactionId: transaction.id))
    }
    
    public func _endSaving(success: Bool, transaction: DatabaseTask.WriteTransaction)
    {
        guard currentSavingTransaction == transaction else { return } // can this even happen?
        currentSavingTransaction = nil
        lastSavingTransactionId = transaction.id
        changedValues.didProcessChangeset(success: success, transaction: transaction)
        self.objectStatus = .stored
        self.lastWrite  = .now
    }
    
    public func _update(with changes: ChangedObject)
    {
        if changes.status == .deleted {
            objectStatus = .deleted
        }
    }
    
    func isSubmitterOf(changes: ChangedObject) -> Bool
    {
        lastSavingTransactionId == changes.transactionId
    }
    
    public func _cascadeDeletion()
    {
        objectStatus = .markedForDeletion
    }
    
    @MainActor
    public func _beginAutoupdating<T: Model>(model: T)
    {
        guard objectChangedNotificationToken == nil else { return }
        objectChangedNotificationToken = DeregisteringNotificationToken(model: model)
    }
}
