import Foundation
import Observation

// Prototype for code enhanced by Macro:
nonisolated final class CarExpanded
{
    let _metadata: ModelMetadata
    let _editableData: EditableData

    var combinedName: String {
        name + "zzz"
    }
    
    //@Stored(defaultValue: { UUID.v7() })
    let id: UUID

    //@Stored(defaultValue: { UUID.v7() })
    let publicId: UUID
    
    //@Related
    //@Backed
    var engine: Engine.Snapshot {
        get { _editableData.engine }
        set {
            guard _editableData.engine != newValue else { return }
            _editableData.engine = newValue
            _metadata.logValueChange(field: "engine", value: newValue)
        }
    }

    // @Related(defaultValue: nil, onDelete: .cascade)
    //@Backed
    var interior: Interior? {
        get { _editableData.interior }
        set {
            guard _editableData.interior != newValue else { return }
            _editableData.interior = newValue
            _metadata.logValueChange(field: "interior", value: newValue)
        }
    }

    // @RelatedMany(Passenger.self, onDelete: .cascade)
    var passengers: RelatedCollection<Passenger> {
        get { _editableData.passengers.collection }
    }

    //@Stored(defaultValue: "asd", fallbackValue: "")
    //@Backed
    var name: String {
        get { _editableData.name }
        set {
            guard _editableData.name != newValue else { return }
            _editableData.name = newValue
            _metadata.logValueChange(field: "name", value: newValue)
        }
    }

    init(db: Database, publicId: UUID = DefaultValues.publicId, name: String = DefaultValues.name, engine: Engine.Snapshot, interior: Interior? = DefaultValues.interior)
    {
        let id = UUID.v7()
        let passengers = ManyToMany<PassengersRelationSchema>(db: db, parentId: id)

        self._metadata = Metadata(db: db, table: Schema.table.name, id: id, isNew: true)
        self._editableData = EditableData(name: name, engine: engine, interior: interior, passengers: passengers)

        self.id = id
        self.publicId = publicId
        
        // Read-only data needs to be added to the changelog, so it will be committed to the database when this object is saved for the first time
        self._metadata.logValueChange(field: "id", value: id)
        self._metadata.logValueChange(field: "publicId", value: publicId)
        self._metadata.logValueChange(field: "name", value: name)
        self._metadata.logValueChange(field: "engine", value: engine)
        self._metadata.logValueChange(field: "interior", value: interior)
    }

    init(db: Database, row: Database.Row) async throws
    {
        let id: UUID = try row.get("id")
        let publicId: UUID = try row.get("publicId")
        let name: String = try row.get("name", fallback: FallbackValues.name)
        let engine: Engine.Snapshot = try await row.get("engine")
        let interior: Interior? = try await row.get("interior")
        let passengers: ManyToMany<PassengersRelationSchema> = try await row.get(parentId: id)
        
        self._metadata = Metadata(db: db, table: Schema.table.name, id: id, isNew: false)
        self._editableData = EditableData(name: name, engine: engine, interior: interior, passengers: passengers)

        self.id = id
        self.publicId = publicId
    }
}

nonisolated extension CarExpanded: Model
{
    @MainActor
    func _beginAutoupdating()
    {
        _metadata._beginAutoupdating(model: self)
        engine._beginAutoupdating()
        interior?._beginAutoupdating()
        _editableData.passengers._beginAutoupdating()
    }

    var _hasPendingChanges: Bool {
        let hasChanges = [
            _metadata._hasPendingChanges,
            engine._hasPendingChanges,
            interior?._hasPendingChanges,
            _editableData.passengers._hasPendingChanges
        ]
        .contains(true)
        return hasChanges
    }
    
    func _beginSaving(changeset: Changeset) throws
    {
        try _metadata._beginSaving(changeset: changeset)
        try engine._beginSaving(changeset: changeset)
        try interior?._beginSaving(changeset: changeset)
        try _editableData.passengers._beginSaving(changeset: changeset)
    }
    
    func _endSaving(success: Bool, transactionId: UUID)
    {
        let wasNew = _metadata.objectStatus == .new
        _metadata._endSaving(success: success, transactionId: transactionId)
        engine._endSaving(success: success, transactionId: transactionId)
        interior?._endSaving(success: success, transactionId: transactionId)
        _editableData.passengers._endSaving(success: success, transactionId: transactionId)
        if wasNew {
            _beginAutoupdatingIfOnMainActor()
        }
    }

    func _update(with changes: ChangedObject) async throws
    {
        _metadata._update(with: changes)
        
        if let updatedFields = changes.updatedFields {
            try await update(field: "name", writableKeyPath: \._editableData.name, newValue: updatedFields["name"])
            try await update(field: "engine", writableKeyPath: \._editableData.engine, newValue: updatedFields["engine"])
            try await update(field: "interior", writableKeyPath: \._editableData.interior, newValue: updatedFields["interior"])
        }
    }
    
    func _cascadeDeletion()
    {
        _metadata._cascadeDeletion()
        interior?._cascadeDeletion()
        _editableData.passengers._cascadeDeletion()
    }


    final class Schema: ModelSchema
    {
        typealias Model = Car
        
        static let related: [any ModelSchema.Type] = [Interior.Schema.self, Engine.Schema.self, Passenger.Schema.self, PassengersRelationSchema.self]
        
        struct Columns
        {
            static let id = RequiredSchema.Column(name: "id", type: UUID.self)
            static let publicId = RequiredSchema.Column(name: "publicId", type: UUID.self)
            static let name = RequiredSchema.Column(name: "name", type: String.self)
            static let engine = RequiredSchema.Column(name: "engine", type: Engine.self, referencedTable: Engine.Model.Schema.table.name)
            static let interior = RequiredSchema.Column(name: "interior", type: Interior.self, referencedTable: Interior.Model.Schema.table.name)
        }

        static let table = RequiredSchema.Table(name: "Car", columns: [
            Columns.id,
            Columns.publicId,
            Columns.name,
            Columns.engine,
            Columns.interior,
        ], indexes: [
            .init(name: "idx_publicId", isUnique: true, columns: [Columns.publicId]),
            .init(name: "idx_engine", isUnique: false, columns: [Columns.engine]),
            .init(name: "idx_interior", isUnique: false, columns: [Columns.interior]),
        ])
    }
    
    struct DefaultValues
    {
        static var name: String { "asd" }
        static var publicId: UUID { UUID.v7() }
        static var interior: Interior? { nil }
    }

    struct FallbackValues
    {
        static var name: String { "" }
    }

    @Observable internal nonisolated final class EditableData
    {
        var name: String
        
        var engine: Engine.Snapshot
        var interior: Interior?
        
        var passengers: ManyToMany<PassengersRelationSchema>

        fileprivate init(name: String, engine: Engine.Snapshot, interior: Interior?, passengers: ManyToMany<PassengersRelationSchema>)
        {
            self.name = name
            self.engine = engine
            self.interior = interior
            self.passengers = passengers
        }
    }

    nonisolated struct QueryProxy
    {
        let id: UUID
        let publicId: UUID
        let name: String
        let engine: Engine
        let interior: Interior?
    }

    nonisolated struct Snapshot: ModelSnapshot
    {
        typealias Model = Car
        
        var combinedName: String {
            name + "zzz"
        }

        let _metadata: SnapshotMetadata<Self>
        
        let id: UUID
        let publicId: UUID
        let name: String

        let _engine: DirectRelationReference<Engine>
        var engine: Engine.Snapshot {
            get async throws {
                try await _metadata.db.resolve(_engine)
            }
        }

        let _interior: DirectRelationReference<Interior>?
        var interior: Interior.Snapshot? {
            get async throws {
                guard let _interior else { return nil }
                return try await _metadata.db.resolve(_interior)
            }
        }

        init(db: Database, row: Database.Row) async throws
        {
            let id: UUID = try row.get("id")
            
            self._metadata = SnapshotMetadata<Self>(id: id, db: db)
            
            self.id = id
            self.publicId = try row.get("publicId")
            self.name = try row.get("name")
            self._engine = try row.get("engine")
            self._interior = try row.get("interior")
        }
    }
}


nonisolated final class PassengersRelationSchema: RelationshipModelSchema
{
    typealias Parent = Car
    typealias Element = Passenger
    typealias Model = ManyToMany<PassengersRelationSchema>.JunctionModel
    
    static let deletionPolicy: DeletionPolicy = .cascade
    
    static let table = RelationshipModelSchemaDefaults.getTable(name: "Car_passengers__Passenger", parentTable: Parent.Schema.table.name, elementTable: Element.Schema.table.name)
    
    static let related: [any ModelSchema.Type] = [Parent.Schema.self, Element.Schema.self]
}
