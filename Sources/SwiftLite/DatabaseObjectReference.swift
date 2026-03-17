import Foundation

public nonisolated struct DatabaseObjectReference<T>: ObjectReference where T: SwiftLite.Model
{
    public typealias Model = T
    
    public let db: Database
    public let id: Model.ID
    
    
    public init(id: T.ID, db: Database, type: T.Type = T.self)
    {
        self.id = id
        self.db = db
    }
    
    public init<F: Fetchable>(_ fetchable: F) where F.Model == T
    {
        self.id = fetchable.id
        self.db = fetchable._metadata.db
    }
    
    public init(_ reference: any ObjectReference, type: T.Type = T.self)
    {
        self.id = reference.id
        self.db = reference.db
    }
    
    public func getObjectReference() -> DatabaseObjectReference<T>
    {
        self
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
