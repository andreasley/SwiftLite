import Foundation

public nonisolated struct SnapshotMetadata<T: ModelSnapshot>: Sendable, DatabaseEntityMetadata
{
    public let id: UUID
    public let db: Database
    public let lastRead: Date? = .now
    
    public init(id: UUID, db: Database)
    {
        self.id = id
        self.db = db
    }
}
