#if canImport(SwiftUI)
import SwiftUI

@MainActor
@propertyWrapper
public struct LiveCollection<T: Fetchable>: @MainActor DynamicProperty
{
    @Environment(Database.self) private var database
    @State private var storage = Storage()

    private let initialPredicate: Predicate<T.Model.QueryProxy>?
    private let initialSortBy: [SortDescriptor<T.Model.QueryProxy>]?
    public var wrappedValue: [T] { storage.results }
    public var projectedValue: Storage { storage }
    
    public init(_ type: T.Type = T.self, where predicate: Predicate<T.Model.QueryProxy>? = nil, sortBy: [SortDescriptor<T.Model.QueryProxy>]? = nil)
    {
        self.initialPredicate = predicate
        self.initialSortBy = sortBy
    }
    
    public func update()
    {
        guard storage.status == .initial else { return }
        
        storage.status = .loading
        if let initialPredicate, storage.`where` == nil {
            storage.`where` = initialPredicate
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

        public var `where`: Predicate<T.Model.QueryProxy>? { didSet { reload() }}
        public var sortBy: [SortDescriptor<T.Model.QueryProxy>]? { didSet { reload() }}

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
                if let `where`, let sortBy {
                    results = try await db.find(T.self, where: `where`, sortBy: sortBy)
                } else if let `where` {
                    results = try await db.find(T.self, where: `where`)
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
