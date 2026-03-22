import Foundation

nonisolated public struct WriteAssociatedData: Sendable, Equatable, Hashable
{
    enum Error: Swift.Error {
        case notFound
    }

    @TaskLocal static var current: WriteAssociatedData?
    
    let db: Database
    let transactionId: UUID = UUID.v7()
    
    public func hash(into hasher: inout Hasher)
    {
        hasher.combine(transactionId)
        hasher.combine(ObjectIdentifier(db))
    }
    
    public static func == (lhs: WriteAssociatedData, rhs: WriteAssociatedData) -> Bool
    {
        lhs.transactionId == rhs.transactionId && ObjectIdentifier(lhs.db) == ObjectIdentifier(rhs.db)
    }
    
    static func getCurrent() throws -> WriteAssociatedData
    {
        guard let current else { throw Error.notFound }
        return current
    }
}

