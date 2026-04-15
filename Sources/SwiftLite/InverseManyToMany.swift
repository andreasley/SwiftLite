import Foundation
import Observation

@Observable
public nonisolated class InverseManyToMany<Schema: RelationshipModelSchema>: Saveable, AnyInverseManyToMany
{
    let db: Database
    let elementId: UUID

    private var notificationToken: AnyDeregisteringNotificationToken?
    public private(set) var collection: RelatedCollection<Schema.Parent.Model.Snapshot>
    private var junctions: [JunctionModel]

    public var _hasPendingChanges: Bool {
        collection.items.contains { $0._hasPendingChanges }
    }
    
    public init<T>(keyPath: KeyPath<T, ManyToMany<Schema>>, db: Database, elementId: UUID) where T == Schema.Parent
    {
        self.db = db
        self.elementId = elementId
        self.collection = RelatedCollection<Schema.Parent.Model.Snapshot>()
        self.junctions = []

        setUpCollectionChangeHandlers()
    }

    public init<T>(keyPath: KeyPath<T, ManyToMany<Schema>>, db: Database, elementId: UUID) async throws where T == Schema.Parent
    {
        self.db = db
        self.elementId = elementId
        let junctions = try await db.find(JunctionModel.self, condition: .byElement(elementId), sortBy: SortDescriptor(\JunctionModel.index, order: .ascending))
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

        self.collection.onMove = { [weak self] source, destination in
            guard let self else { return }
            collection.items.move(fromOffsets: source, toOffset: destination)
            self.updateJunctionIndexes(after: source, destination: destination)
        }
    }

    private func updateJunctionIndexes(after source: IndexSet, destination: Int)
    {
        // Create a mapping of element IDs to their new positions
        let updatedOrder: [UUID] = collection.items.map { $0.id }
        
        // Sort junctions to match the collection order
        let sortedJunctions = updatedOrder.compactMap { parentId in
            junctions.first { $0.parent.id == parentId }
        }
        
        // Check if the order has actually changed by comparing with current junction order
        let currentOrder = junctions.sorted(by: { $0.index < $1.index }).map { $0.parent.id }
        guard currentOrder != updatedOrder else {
            // Order hasn't changed, no need to update indexes
            return
        }
        
        // Determine the range of items that were moved
        let movedCount = source.count
        let destinationStart = destination > source.max()! ? destination - movedCount : destination
                
        // Try to fit moved items in the gap between surrounding items
        if destinationStart > 0 && destinationStart + movedCount < sortedJunctions.count {
            // Moving to middle: try to find gap between items
            let prevIndex = sortedJunctions[destinationStart - 1].index
            let nextIndex = sortedJunctions[destinationStart + movedCount].index
            let gap = nextIndex - prevIndex
            
            if gap > movedCount {
                // We have enough gap to fit all moved items
                let step = gap / (movedCount + 1)
                for i in 0..<movedCount {
                    sortedJunctions[destinationStart + i].index = prevIndex + step * (i + 1)
                }
            } else {
                // Not enough gap, need to reassign all indexes from this point
                reassignIndexesFromPosition(sortedJunctions, startingAt: destinationStart)
            }
        } else if destinationStart == 0 {
            // Moving to beginning
            if sortedJunctions.count > movedCount {
                let nextIndex = sortedJunctions[movedCount].index
                let baseIndex = nextIndex - (movedCount + 1) * 1000
                
                for i in 0..<movedCount {
                    sortedJunctions[i].index = baseIndex + i * 1000
                }
            } else {
                // All items are being moved, just reassign
                reassignIndexesFromPosition(sortedJunctions, startingAt: 0)
            }
        } else {
            // Moving to end
            if destinationStart > 0 {
                let prevIndex = sortedJunctions[destinationStart - 1].index
                let baseIndex = prevIndex + 1000
                
                for i in 0..<movedCount {
                    sortedJunctions[destinationStart + i].index = baseIndex + i * 1000
                }
            } else {
                reassignIndexesFromPosition(sortedJunctions, startingAt: 0)
            }
        }
    }

    private func reassignIndexesFromPosition(_ junctions: [JunctionModel], startingAt position: Int)
    {
        let baseIndex = position > 0 ? junctions[position - 1].index + 1000 : Int(Date.now.timeIntervalSince1970 * 1000)
        
        for i in position..<junctions.count {
            junctions[i].index = baseIndex + (i - position) * 1000
        }
    }

    public nonisolated(nonsending) func _beginSaving(changeset: Changeset) async throws
    {
        for junction in junctions {
            try await junction._beginSaving(changeset: changeset)
        }
    }
    
    public func _endSaving(success: Bool, transactionId: UUID)
    {
        junctions.forEach { $0._endSaving(success: success, transactionId: transactionId) }
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
        junctions.forEach { $0._beginAutoupdating() }

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
            case .updated:
                guard
                    let changedJunction = junctions.first(where: { $0.id == changes.objectId }),
                    let changedField = changes.updatedFields?["index"],
                    let newIndex = try? Int(sqlValue: changedField)
                else { return }
                changedJunction._editableData.index = newIndex
                junctions.sort { $0.index < $1.index }
                let sortedElements = junctions.map { $0.parent }
                collection.items = sortedElements
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
            public let index: Int
            public let _metadata: SnapshotMetadata<Self>
            public let _hasPendingChanges: Bool = false

            public init(db: Database, row: Database.Row) async throws
            {
                fatalError("Not supported")
            }
        }

        public typealias Parent = Schema.Parent

        public var _metadata: ModelMetadata
        
        let _editableData: EditableData

        public let id: UUID
        public var index: Int {
            get {
                _editableData.index
            }
            set {
                guard _editableData.index != newValue else {
                    return
                }
                _editableData.index = newValue
                _metadata.logValueChange(field: "index", value: newValue)
            }
        }
        public let parent: Parent.Model.Snapshot
        public let element: UUID

        public init(db: Database, row: Database.Row) async throws
        {
            let id: UUID = try row.get("id")
            let index: Int = try row.get("index")
            let parent: Parent.Model.Snapshot = try await row.get("parent")
            let element: UUID = try row.get("element")
            
            self._metadata = ModelMetadata(db: db, table: Schema.table.name, id: id, isNew: false)
            self._editableData = EditableData(index: index)

            self.id = id
            self.parent = parent
            self.element = element
        }
        
        public init(db: Database, parent: Parent.Model.Snapshot, element: UUID)
        {
            let id = UUID.v7()
            let index = Int(Date.now.timeIntervalSince1970*1000)

            self._metadata = ModelMetadata(db: db, table: Schema.table.name, id: id, isNew: true)
            self._editableData = EditableData(index: index)

            self.id = id
            self.parent = parent
            self.element = element
            
            // Read-only data needs to be added to the changelog, so it will be committed to the database when this object is saved for the first time
            self._metadata.logValueChange(field: "id", value: id)
            self._metadata.logValueChange(field: "index", value: index)
            self._metadata.logValueChange(field: "parent", value: parent)
            self._metadata.logValueChange(field: "element", value: element)
        }

        @Observable internal nonisolated final class EditableData
        {
            var index: Int

            fileprivate init(index: Int)
            {
                self.index = index
            }
        }

        public nonisolated(nonsending) func _update(with: ChangedObject) async throws
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
        
        public nonisolated(nonsending) func save() async throws
        {
            throw ModelSavingError.directSavingNotSupported
        }
        
        @MainActor
        public func _beginAutoupdating()
        {
            // calling _beginAutoupdating on _metadata is not required, because the junctions can't change and the respective collection will remove them when deleted
            // calling _beginAutoupdating on parent is pointless, since a Snapshot can't autoupdate
        }

        public var _hasPendingChanges: Bool {
            _metadata._hasPendingChanges || parent._hasPendingChanges
        }

        public nonisolated(nonsending) func _beginSaving(changeset: Changeset) async throws
        {
            try _metadata._beginSaving()
            try await parent._beginSaving(changeset: changeset)
        }
        
        public func _endSaving(success: Bool, transactionId: UUID)
        {
            _metadata._endSaving(success: success, transactionId: transactionId)
            parent._endSaving(success: success, transactionId: transactionId)
        }

        public nonisolated struct QueryProxy: SwiftLite.QueryProxy
        {
            let id: UUID
            let index: Int
            let parent: Parent
            let element: UUID
        }
    }
}
