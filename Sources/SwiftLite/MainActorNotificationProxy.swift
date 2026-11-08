import Foundation

@MainActor
public class MainActorNotificationProxy: ActorNotificationProxy
{
    // TODO: Use `AsyncStream`?

    // TODO: Test if notification registration in the property wrapper is quick enough or if there's a risk that some network-synchronized changes get lost

    typealias ModelName = String
    public typealias OnChangeCallback = ((ChangedObject) async throws -> Void)
    
    private static var instances = [ObjectIdentifier: MainActorNotificationProxy]()
    
    public static func get(databaseIdentifier: ObjectIdentifier) -> MainActorNotificationProxy?
    {
        return instances[databaseIdentifier]
    }

    public static func get(db: Database) -> MainActorNotificationProxy
    {
        let databaseIdentifier = ObjectIdentifier(db)
        if let existingInstance = instances[databaseIdentifier] {
            return existingInstance
        } else {
            let newInstance = MainActorNotificationProxy(db: db)
            instances[databaseIdentifier] = newInstance
            return newInstance
        }
    }
    
    let db: Database
    var observers = [ModelName: [Observer]]()
    
    init(db: Database, observers: [ModelName : [Observer]] = [ModelName: [Observer]]())
    {
        self.db = db
        self.observers = observers
        
        Task {
            await db.registerNotificationProxy(self)
        }
    }
    
    internal struct Observer
    {
        let modelName: String
        let objectId: UUID?
        let callback: OnChangeCallback
        let token: NotificationToken
        
        init(modelName: String, objectId: UUID?, token: NotificationToken, callback: @escaping OnChangeCallback)
        {
            self.modelName = modelName
            self.objectId = objectId
            self.token = token
            self.callback = callback
        }
    }
    
    func deregister(token: NotificationToken)
    {
        print("Deregistering", token.modelName)
        let modelName = token.modelName
        guard let previousObservers = observers[modelName] else { return }
        var remainingObservers = previousObservers
        remainingObservers.removeAll { $0.token == token }

        // Keep the previous array alive until the dictionary has been updated. Destroying a removed `Observer`
        // releases the captures of its callback, which may include a `DeregisteringNotificationToken` whose deinit
        // calls `deregister(token:)` again. If that release happened inside the subscript setter, it would be a
        // re-entrant access to `observers` ("Simultaneous accesses ... modification requires exclusive access").
        withExtendedLifetime(previousObservers) {
            observers[modelName] = remainingObservers
        }
    }
    
    func register(modelName: ModelName, objectId: UUID? = nil, callback: @escaping OnChangeCallback) -> NotificationToken
    {
        print("Registering", modelName, objectId as Any)
        let token = NotificationToken(modelName: modelName)
        var observersForModel = observers[modelName] ?? []
        observersForModel.append(Observer(modelName: modelName, objectId: objectId, token: token, callback: callback))
        observers[modelName] = observersForModel
        return token
    }
    
    public func onChange(changeset: FrozenChangeset)
    {
        Task(priority: .medium) { @MainActor in
            for change in changeset.changes {
                try await self.onChange(modelName: change.table, objectId: change.objectId, changes: change)
            }
        }
    }

    func onChange(modelName: String, objectId: UUID?, changes: ChangedObject) async throws
    {
        guard let observersForModel = observers[modelName] else { return }

        for observer in observersForModel {
            guard observer.objectId == objectId || observer.objectId == nil else { continue }
            try await observer.callback(changes)
        }
    }
}

extension MainActorNotificationProxy
{
    public struct NotificationToken: Equatable
    {
        fileprivate let id: UUID
        let modelName: String
        
        init(modelName: String)
        {
            self.id = UUID.v7()
            self.modelName = modelName
        }
    }
}
