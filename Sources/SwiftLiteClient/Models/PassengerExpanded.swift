import SwiftLite
import Foundation
import Observation


// Prototype for code enhanced by Macro:
nonisolated final class PassengerExpanded
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
    
    // @InverseRelatedMany(\Car.passengers)
    var cars: RelatedCollection<Car.Snapshot> {
        get { _editableData.cars.collection }
    }

    init(db: Database, name: String = DefaultValues.name)
    {
        let id = UUID()
        let cars = InverseManyToMany(keyPath: \Car._editableData.passengers, db: db, elementId: id)

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
        let cars: any AnyInverseManyToMany<Car> = try await row.get(inverse: \Car._editableData.passengers, db: db, elementId: id)

        self._metadata = ModelMetadata(db: db, table: Schema.table.name, id: id, isNew: false)
        self._editableData = EditableData(name: name, cars: cars)

        self.id = id
    }
}

nonisolated extension PassengerExpanded: Model
{
    @MainActor
    func _beginAutoupdating()
    {
        _metadata._beginAutoupdating(model: self)
        _editableData.cars._beginAutoupdating()
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

        if let updatedFields = changes.updatedFields {
            try await update(field: "name", writableKeyPath: \._editableData.name, newValue: updatedFields["name"])
        }
    }

    func _cascadeDeletion()
    {
        _metadata._cascadeDeletion()
    }

    nonisolated final class Schema: ModelSchema
    {
        typealias Model = Passenger
        
        static let related: [any ModelSchema.Type] = []

        struct Columns
        {
            static let id = RequiredSchema.Column(name: "id", type: UUID.self)
            static let name = RequiredSchema.Column(name: "name", type: String.self)
        }

        static let table = RequiredSchema.Table(name: "Passenger", columns: [
            Columns.id,
            Columns.name,
        ])
    }
    
    nonisolated struct DefaultValues
    {
        static var name: String { "" }
    }
    
    @Observable nonisolated class EditableData
    {
        var name: String
        var cars: any AnyInverseManyToMany<Car>

        fileprivate init(name: String, cars: any AnyInverseManyToMany<Car> )
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
        typealias Model = Passenger
        
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

