import Foundation

public nonisolated struct DatabaseEntityReference<T: Model>
{
    let db: Database
    let id: UUID
}

public nonisolated extension DatabaseEntityReference
{
    init(from convertible: any DatabaseEntityReferenceConvertible<T>)
    {
        self.db = convertible._metadata.db
        self.id = convertible._metadata.id
    }
}

public nonisolated extension DatabaseEntityReference
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
