import Foundation

// The default read-only type returned from the database
public nonisolated protocol ModelSnapshot: Fetchable, Sendable, SQLValueConvertible, DatabaseEntityReferenceConvertible where Model: SwiftLite.Model
{
    associatedtype Model
    
    var _metadata: SnapshotMetadata<Self> { get }
    var id: UUID { get }
}

public nonisolated extension ModelSnapshot
{
    var _hasPendingChanges: Bool { false }
}

public nonisolated extension ModelSnapshot
{
    func _beginAutoupdating() {}
}
