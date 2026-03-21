import Foundation

public nonisolated struct DatabaseObjectReference<T>: ObjectReference, Hashable where T: SwiftLite.Model
{
    public typealias Model = T
    
    public let db: Database
    public let id: Model.ID
    
    
    public init(id: T.ID, db: Database, type: T.Type = T.self)
    {
        self.id = id
        self.db = db
    }
    
    public init<S: ModelSnapshot>(_ snapshot: S) where S.Model == T
    {
        self.id = snapshot.id
        self.db = snapshot._metadata.db
    }

    public init(_ model: T)
    {
        self.id = model.id
        self.db = model._metadata.db
    }

    public init(_ reference: any ObjectReference, type: T.Type = T.self)
    {
        self.id = reference.id
        self.db = reference.db
    }
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
