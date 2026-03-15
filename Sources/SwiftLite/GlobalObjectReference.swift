import Foundation

public nonisolated struct GlobalObjectReference<T>: ObjectReference where T: SwiftLite.Model
{
    public typealias Model = T
    
    public let id: Model.ID
    
    public init(_ objectReference: any ObjectReference<T>)
    {
        self.id = objectReference.id
    }
    
    public init(id: Model.ID)
    {
        self.id = id
    }
}

public nonisolated extension GlobalObjectReference
{
    enum ResolutionError: Error {
        case notFound
    }
    
    nonisolated(nonsending) func resolve(in db: Database) async throws -> T
    {
        let result = try await db.get(T.self, id: self.id)
        guard let result else { throw ResolutionError.notFound }
        return result
    }
}
