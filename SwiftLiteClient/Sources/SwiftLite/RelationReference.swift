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
