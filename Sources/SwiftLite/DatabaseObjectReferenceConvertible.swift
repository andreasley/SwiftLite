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

nonisolated extension ModelSnapshot
{
    public func getObjectReference() -> DatabaseObjectReference<Self.Model>
    {
        DatabaseObjectReference<Model>(self)
    }
}

nonisolated extension Model
{
    public func getObjectReference() -> DatabaseObjectReference<Self>
    {
        DatabaseObjectReference<Self>(self)
    }
}

nonisolated extension ObjectReference
{
    public func getObjectReference() -> DatabaseObjectReference<Model>
    {
        DatabaseObjectReference(self)
    }
}

extension DatabaseObjectReference
{
    public func getObjectReference() -> DatabaseObjectReference<T>
    {
        self
    }
}
