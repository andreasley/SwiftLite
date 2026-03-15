import Foundation
import Observation

@Observable
public nonisolated class InverseManyToMany<Schema: RelationshipModelSchema>: Saveable, AnyInverseManyToMany
{
    let db: Database
    let elementId: UUID

    private var notificationToken: AnyDeregisteringNotificationToken?
    public private(set) var collection: RelatedCollection<Schema.Parent.Snapshot>
    private var junctions: [JunctionModel]

    public var _hasPendingChanges: Bool {
        collection.items.contains { $0._hasPendingChanges }
    }
    
    public init<T>(keyPath: KeyPath<T, ManyToMany<Schema>>, db: Database, elementId: UUID) where T == Schema.Parent
    {
        self.db = db
        self.elementId = elementId
        self.collection = RelatedCollection<Schema.Parent.Snapshot>()
        self.junctions = []

        setUpCollectionChangeHandlers()
    }

    public init<T>(keyPath: KeyPath<T, ManyToMany<Schema>>, db: Database, elementId: UUID) async throws where T == Schema.Parent
    {
        self.db = db
        self.elementId = elementId
        let junctions = try await db.find(JunctionModel.self, condition: .byElement(elementId))
        self.junctions = junctions
        self.collection = RelatedCollection(items: junctions.map { $0.parent })

        setUpCollectionChangeHandlers()
    }

    func setUpCollectionChangeHandlers()
    {
        self.collection.onAppend = { [weak self] newParent in
            guard let self else { return }
            let newJunction = JunctionModel(db: self.db, parent: newParent, element: self.elementId)
            junctions.append(newJunction)
            collection.items.append(newJunction.parent)
        }

        self.collection.onRemove = { [weak self] removedParent in
            guard let self else { return }
            if let indexOfRemovedParent = collection.items.firstIndex(where: { $0.id == removedParent.id }) {
                collection.items.remove(at: indexOfRemovedParent)
            }
            if let junctionToMarkAsDeleted = junctions.first(where: { $0.parent.id == removedParent.id }) {
                junctionToMarkAsDeleted._cascadeDeletion()
            }
        }
    }

    public func _beginSaving(transaction: DatabaseTask.WriteTransaction, changeset: Changeset) throws
    {
        try junctions.forEach { try $0._beginSaving(transaction: transaction, changeset: changeset) }
    }
    
    public func _endSaving(success: Bool, transaction: DatabaseTask.WriteTransaction)
    {
        junctions.forEach { $0._endSaving(success: success, transaction: transaction) }
        junctions.removeAll { $0._metadata.objectStatus == .deleted }
    }
    
    public func _cascadeDeletion()
    {
        junctions.forEach { $0._cascadeDeletion() }
    }
}

fileprivate extension ChangedObject
{
    func isForElement(_ id: UUID) -> Bool
    {
        guard
            let elementFieldValue = self.updatedFields?["element"],
            case SQLValue.string(let elementIdString) = elementFieldValue,
            let elementId = try? UUID(storageValue: elementIdString),
            elementId == id
        else { return false }
        
        return true
    }
}

@MainActor
extension InverseManyToMany
{
    public func _beginAutoupdating()
    {
        self.notificationToken = DeregisteringNotificationToken(db: db, table: Schema.table.name) { [weak self] changes in
            guard let self else { return }
            switch changes.status {
            case .deleted:
                guard let indexOfJunctionToRemove = junctions.firstIndex(where: { $0.id == changes.objectId }) else { return }
                let junctionToRemove = junctions.remove(at: indexOfJunctionToRemove)
                guard let indexOfParentToRemove = collection.firstIndex(where: { $0.id == junctionToRemove.parent.id }) else { return }
                collection.items.remove(at: indexOfParentToRemove)
            case .created:
                guard changes.isForElement(self.elementId) else { return }
                guard !junctions.contains(where: { $0.id == changes.objectId }) else { return }
                guard let newJunction = try await self.db.get(JunctionModel.self, id: changes.objectId) else { return }
                junctions.append(newJunction)
                collection.items.append(newJunction.parent)
            default:
                // relations can't change; nested objects subscribe themselves for changes
                return
            }
        }
    }
}

public nonisolated extension InverseManyToMany
{
    nonisolated final class JunctionModel: SwiftLite.Model
    {
        nonisolated public struct Snapshot: ModelSnapshot
        {
            public typealias Model = JunctionModel

            public let id: UUID
            public let _metadata: SnapshotMetadata<Self>
            public let _hasPendingChanges: Bool = false

            public init(db: Database, row: Database.Row) async throws
            {
                fatalError("Not supported")
            }
        }

        public typealias Parent = Schema.Parent

        public var _metadata: ModelMetadata
        
        public let id: UUID
        public let parent: Parent.Snapshot
        public let element: UUID

        public init(db: Database, row: Database.Row) async throws
        {
            let id: UUID = try row.get("id")
            let parent: Parent.Snapshot = try await row.get("parent")
            let element: UUID = try row.get("element")
            
            self._metadata = ModelMetadata(db: db, table: Schema.table.name, id: id, isNew: false)
            
            self.id = id
            self.parent = parent
            self.element = element
        }
        
        public init(db: Database, parent: Parent.Snapshot, element: UUID)
        {
            let id = UUID()
            
            self._metadata = ModelMetadata(db: db, table: Schema.table.name, id: id, isNew: true)
            
            self.id = id
            self.parent = parent
            self.element = element
            
            // Read-only data needs to be added to the changelog, so it will be committed to the database when this object is saved for the first time
            self._metadata.logValueChange(field: "id", value: id)
            self._metadata.logValueChange(field: "parent", value: parent)
            self._metadata.logValueChange(field: "element", value: element)
        }

        public func _update(with: ChangedObject) async throws
        {
            throw ModelSavingError.updatingNotSupported
        }
        
        public func _cascadeDeletion()
        {
            _metadata._cascadeDeletion()
            
            // TODO: There's currently no way to cascade deletion on a Snapshot
//            if Schema.deletionPolicy == .cascade {
//                parent._cascadeDeletion()
//            }
        }
        
        public func save() async throws
        {
            throw ModelSavingError.directSavingNotSupported
        }
        
        @MainActor
        public func _beginAutoupdating()
        {
            _metadata._beginAutoupdating(model: self)
            parent._beginAutoupdating()
        }

        public var _hasPendingChanges: Bool {
            _metadata._hasPendingChanges || parent._hasPendingChanges
        }

        public func _beginSaving(transaction: DatabaseTask.WriteTransaction, changeset: Changeset) throws
        {
            try _metadata._beginSaving(transaction: transaction, changeset: changeset)
            try parent._beginSaving(transaction: transaction, changeset: changeset)
        }
        
        public func _endSaving(success: Bool, transaction: DatabaseTask.WriteTransaction)
        {
            _metadata._endSaving(success: success, transaction: transaction)
            parent._endSaving(success: success, transaction: transaction)
        }

        public nonisolated struct QueryProxy: WithNamedKeyPaths
        {
            let id: UUID
            let parent: Parent
            let element: UUID
            
            public static func nameForKeyPath(keyPath: PartialKeyPath<Self>) -> String
            {
                switch keyPath {
                case \.id: "id"
                case \.parent: "parent"
                case \.element: "element"
                default: fatalError("Failed to find name for KeyPath")
                }
            }
        }
    }
}
