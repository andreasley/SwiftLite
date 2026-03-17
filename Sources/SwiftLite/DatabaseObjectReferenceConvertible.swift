public nonisolated protocol DatabaseObjectReferenceConvertible<Model>
{
    associatedtype Model: SwiftLite.Model
    
    func getObjectReference() -> DatabaseObjectReference<Model>
}

public nonisolated extension DatabaseObjectReferenceConvertible
{
    static func byId<T>(_ id: T.ID, db: Database) -> DatabaseObjectReference<T>
    {
        DatabaseObjectReference<T>(id: id, db: db)
    }
}

nonisolated extension Fetchable
{
    public func getObjectReference() -> DatabaseObjectReference<Self.Model>
    {
        DatabaseObjectReference<Model>(self)
    }
}

nonisolated extension ObjectReference
{
    public func getObjectReference() -> DatabaseObjectReference<Model>
    {
        DatabaseObjectReference(self)
    }
}
