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
    var currentWriteAssociatedData: WriteAssociatedData? = nil
    
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
    
    public func hasPendingChange(for fields: String...) -> Bool
    {
        for field in fields {
            if changedValues.hasChange(for: field) {
                return true
            }
        }
        return false
    }

    public func hasNoPendingChange(for fields: String...) -> Bool
    {
        for field in fields {
            if changedValues.hasChange(for: field) {
                return false
            }
        }
        return true
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
    
    public func _beginSaving(changeset: Changeset) throws
    {
        let associatedData = try WriteAssociatedData.getCurrent()
        guard associatedData.db == self.db else { throw ModelSavingError.wrongDatabase }

        guard currentWriteAssociatedData == nil else { throw ModelSavingError.alreadySaving }
        currentWriteAssociatedData = associatedData
        try changeset.append(collectForSaving(transactionId: associatedData.transactionId))
    }
    
    public func _endSaving(success: Bool, transactionId: UUID)
    {
        guard currentWriteAssociatedData?.transactionId == transactionId else { return } // can this even happen?
        currentWriteAssociatedData = nil
        lastSavingTransactionId = transactionId
        changedValues.didProcessChangeset(success: success, transactionId: transactionId)
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
