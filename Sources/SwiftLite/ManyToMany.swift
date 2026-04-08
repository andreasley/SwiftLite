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
        let junctions = try await db.find(JunctionModel.self, condition: .byParent(parentId), sortBy: SortDescriptor(\JunctionModel.index, order: .ascending))
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
        let sortedJunctions = updatedOrder.compactMap { elementId in
            junctions.first { $0.element.id == elementId }
        }
        
        // Check if the order has actually changed by comparing with current junction order
        let currentOrder = junctions.sorted(by: { $0.index < $1.index }).map { $0.element.id }
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
            public let index: Int
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
        public var index: Int {
            didSet { _metadata.logValueChange(field: "index", value: index) }
        }
        public let parent: UUID
        public let element: Element

        public nonisolated(nonsending) init(db: Database, row: Database.Row) async throws
        {
            let id: UUID = try row.get("id")
            let index: Int = try row.get("index")
            let parent: UUID = try row.get("parent")
            let element: Element = try await row.get("element")
            
            self._metadata = ModelMetadata(db: db, table: Schema.table.name, id: id, isNew: false)
            
            self.id = id
            self.index = index
            self.parent = parent
            self.element = element
        }
        
        public init(db: Database, parent: UUID, element: Element)
        {
            let id = UUID.v7()
            
            self._metadata = ModelMetadata(db: db, table: Schema.table.name, id: id, isNew: true)
            
            self.id = id
            self.index = Int(Date.now.timeIntervalSince1970*1000)
            self.parent = parent
            self.element = element
            
            // Read-only data needs to be added to the changelog, so it will be committed to the database when this object is saved for the first time
            self._metadata.logValueChange(field: "id", value: id)
            self._metadata.logValueChange(field: "index", value: index)
            self._metadata.logValueChange(field: "parent", value: parent)
            self._metadata.logValueChange(field: "element", value: element)
        }

        public nonisolated(nonsending) func _update(with: ChangedObject) async throws
        {
            throw ModelSavingError.updatingNotSupported
        }
        
        public func _cascadeDeletion()
        {
            _metadata._cascadeDeletion()
            
            if Schema.deletionPolicy == .cascade, let elementAsModel = element as? (any SwiftLite.Model) {
                elementAsModel._cascadeDeletion()
            }
        }
        
        public nonisolated(nonsending) func save() async throws
        {
            throw ModelSavingError.directSavingNotSupported
        }
        
        @MainActor
        public func _beginAutoupdating()
        {
            // calling _beginAutoupdating on _metadata is not required, because the junctions can't change and the respective collection will remove them when deleted
            if let autoupdatable = element as? AutoupdatingModel {
                autoupdatable._beginAutoupdating()
            }
        }

        public var _hasPendingChanges: Bool {
            _metadata._hasPendingChanges || element._hasPendingChanges
        }

        public nonisolated(nonsending) func _beginSaving(changeset: Changeset) async throws
        {
            try await _metadata._beginSaving(changeset: changeset)
            try await element._beginSaving(changeset: changeset)
        }
        
        public func _endSaving(success: Bool, transactionId: UUID)
        {
            _metadata._endSaving(success: success, transactionId: transactionId)
            element._endSaving(success: success, transactionId: transactionId)
        }

        public nonisolated struct QueryProxy: SwiftLite.QueryProxy
        {
            let id: UUID
            let index: Int
            let parent: UUID
            let element: Element
        }
    }
}

