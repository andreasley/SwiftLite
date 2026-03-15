import Foundation

nonisolated public struct DirectRelationReference<T: Fetchable>: Sendable
{
    public let id: UUID
}
