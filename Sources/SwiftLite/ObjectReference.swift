import Foundation

public protocol ObjectReference<Model>: UnqualifiedObjectReference, DatabaseObjectReferenceConvertible where Model: SwiftLite.Model
{
    associatedtype Model
    
    var id: Model.ID { get }
    var db: Database { get }
}

public nonisolated extension ObjectReference
{
    static func id(id: Model.ID, db: Database) -> DatabaseObjectReference<Model>
    {
        DatabaseObjectReference<Model>(id: id, db: db)
    }
}
