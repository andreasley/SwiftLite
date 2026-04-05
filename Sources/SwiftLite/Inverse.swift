import Foundation
import Observation

@Observable
public nonisolated class Inverse<ReferencingModel: ModelSnapshot, ReferencedModel: Model>: Saveable
{
    let db: Database
    let objectId: UUID
    let referencingField: String
    
    private var notificationToken: AnyDeregisteringNotificationToken?
    public private(set) var collection: RelatedCollection<ReferencingModel>
    
    public init(db: Database, objectId: UUID, referencingField: String)
    {
        self.db = db
        self.objectId = objectId
        self.referencingField = referencingField

        self.collection = RelatedCollection()
        
        // TODO: Add handlers for collection.onAppend/collection.onRemove
    }

    public init(db: Database, objectId: UUID, referencingField: String) async throws
    {
        self.db = db
        self.objectId = objectId
        self.referencingField = referencingField

        let items = try await Self.fetchItems(db: db, referencingField: referencingField, objectId: objectId)
        self.collection = RelatedCollection(items: items)

        // TODO: Add handlers for collection.onAppend/collection.onRemove
    }

    public static nonisolated func fetchItems(db: Database, referencingField: String, objectId: UUID) async throws -> [ReferencingModel]
    {
        try await db.find(ReferencingModel.self, condition: SQLWhereClause(field: referencingField, equals: objectId))
    }

    public var _hasPendingChanges: Bool {
        collection.items.contains { $0._hasPendingChanges }
    }
    
    public nonisolated(nonsending) func _beginSaving(changeset: Changeset) async throws
    {
    }
    
    public func _endSaving(success: Bool, transactionId: UUID)
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
            let items = try await Self.fetchItems(db: db, referencingField: referencingField, objectId: objectId)
            self.collection.items = items
            // TODO: Implement individual updates
        }
    }
}
