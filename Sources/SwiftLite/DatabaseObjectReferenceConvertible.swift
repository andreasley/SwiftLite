import Foundation

public nonisolated protocol DatabaseObjectReferenceConvertible<Model>
{
    associatedtype Model: SwiftLite.Model

    func getObjectReference() -> DatabaseObjectReference<Model>
}

extension Fetchable
{
    public func getObjectReference() -> DatabaseObjectReference<Model>
    {
        DatabaseObjectReference<Self.Model>(db: self._metadata.db, id: self.id)
    }
}

//public nonisolated extension DatabaseEntityReferenceConvertible
//{
//    static func simple(id: Model.ID) -> any DatabaseEntityReferenceConvertible
//    {
//        
//    }
//}
//
//
//public nonisolated struct SimpleDatabaseEntityReference<T: Fetchable>: DatabaseEntityReferenceConvertible
//{
//    public typealias Metadata = T.Metadata
//    public typealias Model = T
//    
//    public let id: T.ID
//    
//    public init(id: T.ID)
//    {
//        self.id = id
//    }
//}
//
//
