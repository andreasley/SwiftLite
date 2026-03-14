import SwiftLite
import Foundation
import Observation

// As coded:
//class Interior
//{
//}

// Prototype for code enhanced by Macro:
nonisolated final class InteriorExpanded
{
    let _metadata: ModelMetadata
    
    let id: UUID
    
    init(db: Database)
    {
        let id = UUID()
        
        self._metadata = ModelMetadata(db: db, table: Schema.table.name, id: id, isNew: true)
        
        self.id = id
        
        // Read-only data needs to be added to the changelog, so it will be committed to the database when this object is saved for the first time
        self._metadata.logValueChange(field: "id", value: id)
    }
    
    init(db: Database, row: Database.Row) async throws
    {
        let id: UUID = try row.get("id")
        
        self._metadata = ModelMetadata(db: db, table: Schema.table.name, id: id, isNew: false)
        
        self.id = id
    }
}

nonisolated extension InteriorExpanded: Model
{
    @MainActor
    func _beginAutoupdating()
    {
        _metadata._beginAutoupdating(model: self)
    }

    var _hasPendingChanges: Bool {
        let hasChanges = [
            _metadata._hasPendingChanges
        ]
        .contains(true)
        return hasChanges
    }

    func _beginSaving(transaction: DatabaseTask.WriteTransaction, changeset: Changeset) throws
    {
        try _metadata._beginSaving(transaction: transaction, changeset: changeset)
    }
    
    func _endSaving(success: Bool, transaction: DatabaseTask.WriteTransaction)
    {
        let wasNew = _metadata.objectStatus == .new
        _metadata._endSaving(success: success, transaction: transaction)
        if wasNew {
            _beginAutoupdatingIfOnMainActor()
        }
    }

    func _update(with changes: ChangedObject) async throws
    {
        _metadata._update(with: changes)
    }
    
    func _cascadeDeletion()
    {
        _metadata._cascadeDeletion()
    }
    
    struct Schema: ModelSchema
    {
        typealias Model = Interior
        
        static let related: [any ModelSchema.Type] = []

        struct Columns
        {
            static let id = RequiredSchema.Column(name: "id", type: UUID.self)
        }

        static let table = RequiredSchema.Table(name: "Interior", columns: [Columns.id])
    }
    
    nonisolated struct QueryProxy: WithNamedKeyPaths
    {
        let id: UUID

        static func nameForKeyPath(keyPath: PartialKeyPath<Self>) -> String
        {
            switch keyPath {
            case \.id: "id"
            default: fatalError("Failed to find name for KeyPath")
            }
        }
    }

    nonisolated struct Snapshot: ModelSnapshot
    {
        typealias Model = Interior
        
        let _metadata: SnapshotMetadata<Self>

        let id: UUID
        
        init(db: Database, row: Database.Row) async throws
        {
            let id: UUID = try row.get("id")
            
            self._metadata = SnapshotMetadata<Self>(id: id, db: db)

            self.id = id
        }
    }
}

