import Foundation
import Observation
import SwiftLite

// Prototype for code enhanced by Macro:
nonisolated final class EngineExpanded
{
    let _metadata: ModelMetadata
    let _editableData: EditableData
    
    //@Stored(defaultValue: "")
    let id: UUID
    
    //@Stored(defaultValue: "")
    //@Backed
    var name: String {
        get { _editableData.name }
        set {
            guard _editableData.name != newValue else { return }
            _editableData.name = newValue
            _metadata.logValueChange(field: "name", value: newValue)
        }
    }
    
    // @InverseRelated(\Car.engine)
    var cars: RelatedCollection<Car.Snapshot> {
        get { _editableData.cars.collection }
    }

    init(db: Database, name: String = DefaultValues.name)
    {
        let id = UUID()
        let cars = Inverse<Car.Snapshot, Engine>(db: db, objectId: id, referencingField: "engine")
        
        self._metadata = ModelMetadata(db: db, table: Schema.table.name, id: id, isNew: true)
        self._editableData = EditableData(name: name, cars: cars)
        
        self.id = id
        
        // Read-only data needs to be added to the changelog, so it will be committed to the database when this object is saved for the first time
        self._metadata.logValueChange(field: "id", value: id)
        self._metadata.logValueChange(field: "name", value: name)
    }
    
    init(db: Database, row: Database.Row) async throws
    {
        let id: UUID = try row.get("id")
        let name: String = try row.get("name")
        let cars: Inverse<Car.Snapshot, Engine> = try await row.get(objectId: id, referencingField: "engine")

        self._metadata = ModelMetadata(db: db, table: Schema.table.name, id: id, isNew: false)
        self._editableData = EditableData(name: name, cars: cars)
        
        self.id = id
    }
}

nonisolated extension EngineExpanded: Model
{
    @MainActor
    func _beginAutoupdating()
    {
        _metadata._beginAutoupdating(model: self)
        _editableData.cars._beginAutoupdating()
    }

    var _hasPendingChanges: Bool {
        let hasChanges = [
            _metadata._hasPendingChanges,
            _editableData.cars._hasPendingChanges,
        ]
        .contains(true)
        return hasChanges
    }

    func _beginSaving(changeset: Changeset) throws
    {
        try _metadata._beginSaving(changeset: changeset)
        try _editableData.cars._beginSaving(changeset: changeset)
    }
    
    func _endSaving(success: Bool, transactionId: UUID)
    {
        let wasNew = _metadata.objectStatus == .new
        _metadata._endSaving(success: success, transactionId: transactionId)
        _editableData.cars._endSaving(success: success, transactionId: transactionId)
        if wasNew {
            _beginAutoupdatingIfOnMainActor()
        }
    }

    func _update(with changes: ChangedObject) async throws
    {
        _metadata._update(with: changes)

        if let updatedFields = changes.updatedFields {
            try await update(field: "name", writableKeyPath: \._editableData.name, newValue: updatedFields["name"])
        }
    }

    func _cascadeDeletion()
    {
        _metadata._cascadeDeletion()
    }

    nonisolated struct Schema: ModelSchema
    {
        typealias Model = Engine
        
        static let related: [any ModelSchema.Type] = []

        struct Columns
        {
            static let id = RequiredSchema.Column(name: "id", type: UUID.self)
            static let name = RequiredSchema.Column(name: "name", type: String.self)
        }

        static let table = RequiredSchema.Table(name: "Engine", columns: [
            Columns.id,
            Columns.name,
        ])
    }
    
    nonisolated struct DefaultValues
    {
        static var name: String { "" }
    }
    
    @Observable internal nonisolated class EditableData
    {
        var name: String

        let cars: Inverse<Car.Snapshot, Engine>

        fileprivate init(name: String, cars: Inverse<Car.Snapshot, Engine>)
        {
            self.name = name
            self.cars = cars
        }
    }
    
    nonisolated struct QueryProxy: WithNamedKeyPaths
    {
        let id: UUID
        let name: String

        static func nameForKeyPath(keyPath: PartialKeyPath<Self>) -> String
        {
            return switch keyPath {
            case \.id: "id"
            case \.name: "name"
            default: fatalError("Failed to find name for KeyPath")
            }
        }
    }

    nonisolated struct Snapshot: ModelSnapshot
    {
        typealias Model = Engine
        
        let _metadata: SnapshotMetadata<Self>

        let id: UUID
        let name: String

        init(db: Database, row: Database.Row) async throws
        {
            let id: UUID = try row.get("id")
            
            self._metadata = SnapshotMetadata<Self>(id: id, db: db)

            self.id = id
            self.name = try row.get("name")
        }
    }
}

