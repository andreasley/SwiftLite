import Foundation

@MainActor
public class DeregisteringNotificationToken: AnyDeregisteringNotificationToken
{
    let notificationToken: MainActorNotificationProxy.NotificationToken
    let databaseIdentifier: ObjectIdentifier
    
    public init(db: Database, table: String, objectId: UUID? = nil, callback: @escaping MainActorNotificationProxy.OnChangeCallback)
    {
        let proxy = MainActorNotificationProxy.get(db: db)

        self.databaseIdentifier = ObjectIdentifier(db)
        self.notificationToken = proxy.register(modelName: table, objectId: objectId, callback: callback)
    }

    public convenience init<T: Model>(model: T)
    {
        let db = model._metadata.db
        let table = T.Schema.table.name
        let objectId = model.id

        self.init(db: db, table: table, objectId: objectId) { [weak model] changes in
            guard let model else { return }
            guard !model._metadata.isSubmitterOf(changes: changes) else { return }
            try? await model._update(with: changes)
            // Probably can't surface any errors to the UI, because the only way for that would have been through the model
        }
    }


    @MainActor
    deinit
    {
        MainActorNotificationProxy.get(databaseIdentifier: databaseIdentifier)?.deregister(token: notificationToken)
    }
}

protocol AnyDeregisteringNotificationToken: AnyObject {}
