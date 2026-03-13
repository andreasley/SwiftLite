import Foundation
import Observation

@Observable
public nonisolated class ManyToMany<Schema: RelationshipModelSchema>: Saveable
{
    let db: Database
    let parentId: UUID

    private var notificationToken: AnyDeregisteringNotificationToken?
    private var _collection: Collection

    public var collection: Collection {
        get { _collection }
        set { _collection = newValue }
    }
    
    public var _hasPendingChanges: Bool {
        _collection._hasPendingChanges
    }
    
    init(db: Database, parentId: UUID)
    {
        self.db = db
        self.parentId = parentId
        self._collection = Collection(db: db, parentId: parentId, items: [])
    }
    
    init(db: Database, parentId: UUID) async throws
    {
        let items = try await db.find(RelationshipModel.self, condition: .byParent(parentId))
        self.db = db
        self.parentId = parentId
        self._collection = Collection(db: db, parentId: parentId, items: items)
    }

    public func _beginSaving(transaction: DatabaseTask.WriteTransaction, changeset: Changeset) throws
    {
        try _collection._beginSaving(transaction: transaction, changeset: changeset)
    }
    
    public func _endSaving(success: Bool, transaction: DatabaseTask.WriteTransaction)
    {
        _collection._endSaving(success: success, transaction: transaction)
    }
    
    public func _cascadeDeletion()
    {
        _collection._cascadeDeletion()
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
        collection._beginAutoupdating()
        self.notificationToken = DeregisteringNotificationToken(db: db, table: Schema.table.name) { [weak self] changes in
            guard let self else { return }
            switch changes.status {
            case .deleted:
                self.collection.removeRelation(id: changes.objectId)
            case .created:
                guard changes.isForParent(self.parentId) else { return }
                guard !self.collection.containsRelation(id: changes.objectId) else { return }
                guard let newRelation = try await self.db.get(RelationshipModel.self, id: changes.objectId) else { return }
                self.collection.appendRelation(newRelation)
            default:
                // relations can't change; nested objects subscribe themselves for changes
                return
            }
        }
    }
}

public nonisolated extension ManyToMany
{
    nonisolated final class RelationshipModel: SwiftLite.Model
    {
        nonisolated public struct Snapshot: ModelSnapshot
        {
            public typealias Model = RelationshipModel

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
            try element._beginSaving(transaction: transaction, changeset: changeset)
            try _metadata._beginSaving(transaction: transaction, changeset: changeset)
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

    
public nonisolated extension ManyToMany
{
    nonisolated struct Collection: RandomAccessCollection
    {
        public typealias Element = Schema.Element
        
        public private(set) var items: [RelationshipModel]
        public private(set) var visibleItems: [RelationshipModel]
        
        public var startIndex: Int { visibleItems.startIndex }
        public var endIndex: Int { visibleItems.endIndex }
        
        let db: Database
        let parentId: UUID
        
        fileprivate init(db: Database, parentId: UUID, items: [RelationshipModel] = [])
        {
            self.db = db
            self.parentId = parentId
            self.items = items
            self.visibleItems = items
        }
        
        public mutating func append(_ element: Element)
        {
            let new = RelationshipModel(db: db, parent: parentId, element: element)
            items.append(new)
            visibleItems.append(new)
        }
        
        public mutating func remove(at index: Int) -> Element
        {
            let relationEntry = visibleItems.remove(at: index)
            
            if relationEntry._metadata.objectStatus == .new {
                if let indexInItems = items.firstIndex(of: relationEntry) {
                    items.remove(at: indexInItems)
                }
            } else {
                relationEntry._metadata._cascadeDeletion()
                relationEntry._cascadeDeletion()
            }
            
            return relationEntry.element
        }
        
        @discardableResult
        public mutating func remove(_ element: Element) -> Element?
        {
            guard let index = visibleItems.firstIndex(where: { $0.element == element }) else { return nil }
            return remove(at: index)
        }
        
        internal mutating func containsRelation(id: UUID) -> Bool
        {
            items.contains { $0.id == id }
        }
        
        internal mutating func removeRelation(id: UUID)
        {
            items.removeAll { $0.id == id }
            visibleItems.removeAll { $0.id == id }
        }
        
        internal mutating func appendRelation(_ relation: RelationshipModel)
        {
            items.append(relation)
            visibleItems.append(relation)
        }
        
        public subscript(index: Int) -> Element
        {
            get { visibleItems[index].element }
        }
        
        public var _hasPendingChanges: Bool {
            items.contains { $0._hasPendingChanges }
        }
        
        public func _beginSaving(transaction: DatabaseTask.WriteTransaction, changeset: Changeset) throws
        {
            try items.forEach { try $0._beginSaving(transaction: transaction, changeset: changeset) }
        }
        
        public mutating func _endSaving(success: Bool, transaction: DatabaseTask.WriteTransaction)
        {
            items.forEach { $0._endSaving(success: success, transaction: transaction) }
            items.removeAll { $0._metadata.objectStatus == .deleted }
        }
        
        public func _cascadeDeletion()
        {
            items.forEach { $0._cascadeDeletion() }
        }
        
        @MainActor
        public func _beginAutoupdating()
        {
            items.forEach { $0._beginAutoupdating() }
        }
    }
}
