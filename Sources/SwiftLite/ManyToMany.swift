import Foundation
import Observation

@Observable
public nonisolated class ManyToMany<Schema: RelationshipModelSchema>: Saveable
{
    let db: Database
    let parentId: UUID

    private var notificationToken: AnyDeregisteringNotificationToken?
    public private(set) var collection: RelatedCollection<Schema.Element>
    private var junctions: [JunctionModel]

    
    public var _hasPendingChanges: Bool {
        junctions.contains { $0._hasPendingChanges }
    }
    
    public init(db: Database, parentId: UUID)
    {
        self.db = db
        self.parentId = parentId
        self.junctions = []
        self.collection = RelatedCollection(items: [])

        setUpCollectionChangeHandlers()
    }
    
    public init(db: Database, parentId: UUID) async throws
    {
        self.db = db
        self.parentId = parentId
        let junctions = try await db.find(JunctionModel.self, condition: .byParent(parentId))
        self.junctions = junctions
        self.collection = RelatedCollection(items: junctions.map { $0.element })
        
        setUpCollectionChangeHandlers()
    }
    
    func setUpCollectionChangeHandlers()
    {
        self.collection.onAppend = { [weak self] newElement in
            guard let self else { return }
            let newJunction = JunctionModel(db: self.db, parent: self.parentId, element: newElement)
            junctions.append(newJunction)
            collection.items.append(newJunction.element)
        }

        self.collection.onRemove = { [weak self] removedElement in
            guard let self else { return }
            if let indexOfElementToRemove = collection.items.firstIndex(where: { $0.id == removedElement.id }) {
                collection.items.remove(at: indexOfElementToRemove)
            }
            if let junctionToMarkAsDeleted = junctions.first(where: { $0.element.id == removedElement.id }) {
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
    func isForParent(_ id: UUID) -> Bool
    {
        guard
            let parentFieldValue = self.updatedFields?["parent"],
            case SQLValue.string(let parentIdString) = parentFieldValue,
            let parentId = try? UUID(storageValue: parentIdString),
            parentId == id
        else { return false }
        
        return true
    }
}

@MainActor
extension ManyToMany
{
    public func _beginAutoupdating()
    {
        junctions.forEach { $0._beginAutoupdating() }
        
        self.notificationToken = DeregisteringNotificationToken(db: db, table: Schema.table.name) { [weak self] changes in
            guard let self else { return }
            switch changes.status {
            case .deleted:
                guard let indexOfJunctionToRemove = junctions.firstIndex(where: { $0.id == changes.objectId }) else { return }
                let junctionToRemove = junctions.remove(at: indexOfJunctionToRemove)
                guard let indexOfElementToRemove = collection.firstIndex(where: { $0.id == junctionToRemove.element.id }) else { return }
                collection.items.remove(at: indexOfElementToRemove)
            case .created:
                guard changes.isForParent(self.parentId) else { return }
                guard !junctions.contains(where: { $0.id == changes.objectId }) else { return }
                guard let newJunction = try await self.db.get(JunctionModel.self, id: changes.objectId) else { return }
                junctions.append(newJunction)
                collection.items.append(newJunction.element)
            default:
                // relations can't change; nested objects subscribe themselves for changes
                return
            }
        }
    }
}

public nonisolated extension ManyToMany
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

        public typealias Element = Schema.Element

        public var _metadata: ModelMetadata
        
        public let id: UUID
        public let parent: UUID
        public let element: Element

        public init(db: Database, row: Database.Row) async throws
        {
            let id: UUID = try row.get("id")
            let parent: UUID = try row.get("parent")
            let element: Element = try await row.get("element")
            
            self._metadata = ModelMetadata(db: db, table: Schema.table.name, id: id, isNew: false)
            
            self.id = id
            self.parent = parent
            self.element = element
        }
        
        public init(db: Database, parent: UUID, element: Element)
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
            
            if Schema.deletionPolicy == .cascade {
                element._cascadeDeletion()
            }
        }
        
        public func save() async throws
        {
            throw ModelSavingError.directSavingNotSupported
        }
        
        @MainActor
        public func _beginAutoupdating()
        {
            _metadata._beginAutoupdating(model: self)
            element._beginAutoupdating()
        }

        public var _hasPendingChanges: Bool {
            _metadata._hasPendingChanges || element._hasPendingChanges
        }

        public func _beginSaving(transaction: DatabaseTask.WriteTransaction, changeset: Changeset) throws
        {
            try _metadata._beginSaving(transaction: transaction, changeset: changeset)
            try element._beginSaving(transaction: transaction, changeset: changeset)
        }
        
        public func _endSaving(success: Bool, transaction: DatabaseTask.WriteTransaction)
        {
            _metadata._endSaving(success: success, transaction: transaction)
            element._endSaving(success: success, transaction: transaction)
        }

        public nonisolated struct QueryProxy: WithNamedKeyPaths
        {
            let id: UUID
            let parent: UUID
            let element: Element
            
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

