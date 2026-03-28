import Foundation

public protocol ObjectReference<Model>: UnqualifiedObjectReference, DatabaseObjectReferenceConvertible, Sendable where Model: SwiftLite.Model
{
    associatedtype Model
    
    var id: Model.ID { get }
    var db: Database { get }
    
    func resolve() async throws -> Model
}

enum ObjectReferenceResolutionError: Error {
    case notFound
}

public nonisolated extension ObjectReference
{
    static func id(id: Model.ID, db: Database) -> DatabaseObjectReference<Model>
    {
        DatabaseObjectReference<Model>(id: id, db: db)
    }
    
    nonisolated(nonsending) func resolve() async throws -> Model
    {
        let result = try await db.get(Model.self, id: self.id)
        guard let result else { throw ObjectReferenceResolutionError.notFound }
        return result
    }
}
