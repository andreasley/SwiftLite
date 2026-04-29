#if canImport(SwiftUI)
import SwiftUI

@MainActor
@propertyWrapper
public struct LiveCollection<T: Fetchable>: @MainActor DynamicProperty
{
    @Environment(Database.self) private var database
    @State private var storage = Storage()

    private let initialFilter: SQLWhereClauseConvertible?
    private let initialSortBy: SQLSortClauseConvertible?
    private let initialLimit: Int?
    public var wrappedValue: [T] { storage.results }
    public var projectedValue: Storage { storage }
    
    public init(_ type: T.Type = T.self, filter: SQLWhereClauseConvertible? = nil, sortBy: SQLSortClauseConvertible? = nil, limit: Int? = nil)
    {
        self.initialFilter = filter
        self.initialSortBy = sortBy
        self.initialLimit = limit
    }
    
    public func update()
    {
        guard storage.status == .initial else { return }
        
        storage.status = .loading
        if let initialFilter, storage.filter == nil {
            storage.filter = initialFilter
        }
        if let initialSortBy, storage.sortBy == nil {
            storage.sortBy = initialSortBy
        }
        if let initialLimit, storage.limit == nil {
            storage.limit = initialLimit
        }

        Task {
            await storage.load(from: database)
        }
    }

    @Observable
    @MainActor
    public class Storage
    {
        public var status: LoadingStatus = .initial
        public var results: [T] = []

        public var filter: SQLWhereClauseConvertible? { didSet { reload() }}
        public var sortBy: SQLSortClauseConvertible? { didSet { reload() }}
        public var limit: Int? { didSet { reload() }}

        @ObservationIgnored
        public var database: Database?
        
        @ObservationIgnored
        var notificationToken: DeregisteringNotificationToken?
        
        private func reload()
        {
            guard let database else { return }
            Task {
                await load(from: database)
            }
        }

        public func load(from db: Database) async
        {
            self.database = db
            
            if notificationToken == nil {
                self.notificationToken = DeregisteringNotificationToken(db: db, table: T.Model.Schema.table.name) { [weak self] changes in
                    guard let self else { return }
                    switch changes.status {
                    case .created:
                        Task {
                            // Simply refresh the whole list
                            // TODO: Optimize
                            await self.load(from: db)
                        }
                    case .deleted:
                        if let indexOfEntry = self.results.firstIndex(where: { $0.id == changes.objectId }) {
                            self.results.remove(at: indexOfEntry)
                        }
                    case .updated:
                        if let indexOfEntry = self.results.firstIndex(where: { $0.id == changes.objectId }), let newObject = try await db.get(T.self, id: changes.objectId) {
                            self.results[indexOfEntry] = newObject
                        }
                    }
                }
            }
            
            status = .loading
            
            do {
                if let filter {
                    results = try await db.find(T.self, where: filter, sortBy: sortBy, limit: limit)
                } else {
                    results = try await db.get(T.self, sortBy: sortBy, limit: limit)
                }

                status = .loaded
            } catch {
                status = .loadingError(error)
            }
        }
    }
}

#endif
