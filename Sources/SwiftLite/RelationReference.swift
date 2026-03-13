import Foundation

nonisolated public protocol RelationReference<T>
{
    associatedtype T
}

nonisolated public struct DirectRelationReference<T: Model>: RelationReference, Sendable
{
    public let id: UUID
}
