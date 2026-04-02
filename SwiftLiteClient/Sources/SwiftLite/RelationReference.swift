import Foundation

nonisolated public struct DirectRelationReference<T: Fetchable>: Sendable
{
    public let id: UUID
}

extension DirectRelationReference: Equatable
{
    public static func == (lhs: DirectRelationReference, rhs: DirectRelationReference) -> Bool
    {
        lhs.id == rhs.id
    }
}

extension DirectRelationReference
{
    public func resolve<Result>(as type: Result.Type, in db: Database) async throws -> Result? where Result: Fetchable, Result.Model == T.Model
    {
        try await db.get(type, id: id)
    }
}
