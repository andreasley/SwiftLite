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
    public var wrappedValue: [T] { storage.results }
    public var projectedValue: Storage { storage }
    
    public init(_ type: T.Type = T.self, filter: SQLWhereClauseConvertible? = nil, sortBy: [SortDescriptor<T.Model.QueryProxy>]? = nil)
    {
        self.initialFilter = filter
        self.initialSortBy = sortBy?.toSQL()
    }

    public init(_ type: T.Type = T.self, filter: SQLWhereClauseConvertible? = nil, sortBy: SQLSortClauseConvertible? = nil)
    {
        self.initialFilter = filter
        self.initialSortBy = sortBy
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
                    Task {
                        // Simply refresh the whole list
                        await self?.load(from: db)
                    }
                    // TODO: Implement per-row updates?
                }
            }
            
            status = .loading
            
            do {
                if let filter, let sortBy {
                    results = try await db.find(T.self, where: filter, sortBy: sortBy)
                } else if let filter {
                    results = try await db.find(T.self, where: filter)
                } else if let sortBy {
                    results = try await db.get(T.self, sortBy: sortBy)
                } else {
                    results = try await db.get(T.self)
                }

                status = .loaded
            } catch {
                status = .loadingError(error)
            }
        }
    }
}

#endif
