import Foundation
import Observation

@Observable
public nonisolated class Inverse<ReferencingModel: ModelSnapshot, ReferencedModel: Model>: Saveable
{
    let db: Database
    let objectId: UUID
    let referencingField: String
    
    private var notificationToken: AnyDeregisteringNotificationToken?
    private var _items: Collection
    
    var items: Collection {
        get { _items }
        set { _items = newValue }
    }

    init(db: Database, objectId: UUID, referencingField: String)
    {
        self.db = db
        self.objectId = objectId
        self.referencingField = referencingField

        self._items = Collection()
    }

    init(db: Database, objectId: UUID, referencingField: String) async throws
    {
        self.db = db
        self.objectId = objectId
        self.referencingField = referencingField

        self._items = Collection(items: try await Self.fetchItems(db: db, referencingField: referencingField, objectId: objectId))
    }

    public static nonisolated func fetchItems(db: Database, referencingField: String, objectId: UUID) async throws -> [ReferencingModel]
    {
        try await db.find(ReferencingModel.self, condition: .init(field: referencingField, value: .string(objectId.storageValue)))
    }

    public var _hasPendingChanges: Bool { false }
    
    public func _beginSaving(transaction: DatabaseTask.WriteTransaction, changeset: Changeset) throws
    {
    }
    
    public func _endSaving(success: Bool, transaction: DatabaseTask.WriteTransaction)
    {
    }
    
    public func _cascadeDeletion()
    {
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
extension Inverse
{
    public func _beginAutoupdating()
    {
        self.notificationToken = DeregisteringNotificationToken(db: db, table: ReferencingModel.Model.Schema.table.name) { [weak self] changes in
            guard let self else { return }
            self._items = try await Collection(items: Self.fetchItems(db: db, referencingField: referencingField, objectId: objectId))
            // TODO: Implement individual updates
        }
    }
}

    
public nonisolated extension Inverse
{
    nonisolated struct Collection: RandomAccessCollection
    {
        public typealias Element = ReferencingModel
        
        public internal(set) var items: [Element]
        
        public var startIndex: Int { items.startIndex }
        public var endIndex: Int { items.endIndex }
        
        fileprivate init(items: [Element] = [])
        {
            self.items = items
        }
        
        public subscript(index: Int) -> Element {
            get { items[index] }
        }
        
        public var _hasPendingChanges: Bool {
            items.contains { $0._hasPendingChanges }
        }
        
        public func _beginSaving(transaction: DatabaseTask.WriteTransaction, changeset: Changeset) throws
        {
//            try items.forEach { try $0._beginSaving(transaction: transaction, changeset: changeset) }
        }
        
        public mutating func _endSaving(success: Bool, transaction: DatabaseTask.WriteTransaction)
        {
//            items.forEach { $0._endSaving(success: success, transaction: transaction) }
//            items.removeAll { $0._metadata.isDeleted && !$0._metadata.statusIsUnsaved }
        }
        
        public func _cascadeDeletion()
        {
//            items.forEach { $0._cascadeDeletion() }
        }
    }
}
