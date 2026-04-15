import Foundation

public nonisolated protocol Model: AnyObject, Fetchable, Observable, @MainActor AutosavingModel, @MainActor AutoupdatingModel, Saveable
{
    associatedtype Model = Self
    associatedtype QueryProxy: SwiftLite.QueryProxy
    associatedtype Snapshot: ModelSnapshot
    associatedtype Schema: ModelSchema
    
    var _metadata: ModelMetadata { get }
    
    func _cascadeDeletion()
    
    @MainActor
    func _update(with: ChangedObject) async throws
}

public nonisolated extension Model
{
    nonisolated(nonsending) func save() async throws
    {
        self._metadata.autosaveTask?.cancel()
        
        guard _hasPendingChanges else { return }
        
        let associatedData = WriteAssociatedData(db: _metadata.db)
        try await WriteAssociatedData.$current.withValue(associatedData, operation: _save)
    }
    
    nonisolated(nonsending) private func _save() async throws
    {
        let associatedData = try WriteAssociatedData.getCurrent()
        var success = false
        let changeset = Changeset()
        try await self._beginSaving(changeset: changeset)
        defer { self._endSaving(success: success, transactionId: associatedData.transactionId) }
        if changeset.needsSaving {
            let frozenChangeset = FrozenChangeset(changes: changeset.changes)
            try await associatedData.db.save(changeset: frozenChangeset)
        }
        success = true
    }

    nonisolated(nonsending) func delete() async throws
    {
        _cascadeDeletion()
        try await self.save()
    }

    nonisolated(nonsending) func update<V>(field: String, writableKeyPath: ReferenceWritableKeyPath<Self, V>, newValue: SQLValue?) async throws where V: SQLValueConvertible
    {
        guard let newValue else { return }
        guard _metadata.hasNoPendingChange(for: field) else { return }
        let value: V = try await .init(db: self._metadata.db, sqlValue: newValue)
        self[keyPath: writableKeyPath] = value
    }
}

public extension Model where Self: AutoupdatingModel
{
    nonisolated func _beginAutoupdatingIfOnMainActor()
    {
        guard Thread.isMainThread else { return }
        nonisolated(unsafe) let unsafeSelf = self
        MainActor.assumeIsolated {
            unsafeSelf._beginAutoupdating()
        }
    }
}

public extension Model
{
    var hasBeenDeletedFromDatabase: Bool { _metadata.objectStatus == .deleted }
}

public nonisolated enum ModelSavingError: Swift.Error {
    case alreadySaving
    case wrongDatabase
    case directSavingNotSupported
    case updatingNotSupported
}
