import Foundation

public nonisolated struct DatabaseObjectReference<T>: ObjectReference where T: SwiftLite.Model
{
    public typealias Model = T
    
    public let db: Database
    public let id: Model.ID
}

public nonisolated extension DatabaseObjectReference
{
    enum ResolutionError: Error {
        case notFound
    }
    
    nonisolated(nonsending) func resolve() async throws -> T
    {
        let result = try await db.get(T.self, id: self.id)
        guard let result else { throw ResolutionError.notFound }
        return result
    }
}
