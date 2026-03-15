#if canImport(SwiftUI)
import SwiftUI
import SwiftLite

@MainActor
@propertyWrapper
public struct LiveCollection<T: Fetchable>: @MainActor DynamicProperty
{
    public typealias Predicate = (Query<T>.Proxy) -> Query<T>.Proxy.Predicate

    @Environment(Database.self) private var database
    @State private var storage = Storage()

    private let predicate: Predicate?
    public var wrappedValue: [T] { storage.results }
    public var projectedValue: Storage { storage }
    
    public init(_ type: T.Type = T.self, where predicate: Predicate? = nil)
    {
        self.predicate = predicate
    }
    
    public func update()
    {
        guard storage.status == .initial else { return }
        
        storage.status = .loading

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

        public var predicate: Predicate?

        @ObservationIgnored
        public var database: Database?
        
        @ObservationIgnored
        var notificationToken: DeregisteringNotificationToken?

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
                if let predicate {
                    results = try await db.find(T.self, where: predicate)
                } else {
                    results = try await db.get(T.self)
                }

                status = .loaded
            } catch {
                status = .error(error)
            }
        }
    }
}

#endif
