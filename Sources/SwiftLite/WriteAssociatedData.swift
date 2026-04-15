import Foundation

nonisolated public struct WriteAssociatedData: Sendable, Equatable, Hashable
{
    enum Error: Swift.Error {
        case notFound
        case isolationMismatch
    }
    
    @TaskLocal static var current: WriteAssociatedData?
    
    let db: Database
    let transactionId: UUID = UUID.v7()
    let savingData: SavingData
    
    init(db: Database, isolation: isolated (any Actor)? = #isolation)
    {
        self.db = db
        self.savingData = SavingData(db: db, transactionId: transactionId, isolation: isolation)
    }
    
    public func hash(into hasher: inout Hasher)
    {
        hasher.combine(transactionId)
        hasher.combine(ObjectIdentifier(db))
    }
    
    public static func == (lhs: WriteAssociatedData, rhs: WriteAssociatedData) -> Bool
    {
        lhs.transactionId == rhs.transactionId && ObjectIdentifier(lhs.db) == ObjectIdentifier(rhs.db)
    }
    
    static func getSavingData(isolation: isolated (any Actor)? = #isolation) throws -> SavingData
    {
        guard let current else { throw Error.notFound }
        guard current.savingData.isolation === isolation else { throw Error.isolationMismatch }
        return current.savingData
    }
}

class SavingData: @unchecked Sendable
{
    typealias SaveCompletedCallback = (Bool) -> Void
    
    var changeset: Changeset
    private var callbacks: [SaveCompletedCallback] = []
    let isolation: (any Actor)?
    let transactionId: UUID
    let db: Database
    
    init(db: Database, transactionId: UUID, isolation: isolated (any Actor)? = #isolation)
    {
        self.db = db
        self.isolation = isolation
        self.transactionId = transactionId
        self.changeset = Changeset(isolation: isolation)
    }
    
    func notifyObjectsAboutResult(success: Bool)
    {
        for callback in callbacks {
            callback(success)
        }
    }
    
    func onSaveCompleted(_ callback: @escaping SaveCompletedCallback)
    {
        callbacks.append(callback)
    }
}
