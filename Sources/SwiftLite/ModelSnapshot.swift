import Foundation

// The default read-only type returned from the database
public nonisolated protocol ModelSnapshot: Fetchable, Sendable, SQLValueConvertible, DatabaseObjectReferenceConvertible where Model: SwiftLite.Model
{
    associatedtype Model
    
    var _metadata: SnapshotMetadata<Self> { get }
}

public nonisolated extension ModelSnapshot
{
    var _hasPendingChanges: Bool { false }
}

public nonisolated extension ModelSnapshot
{
    func _beginAutoupdating() {}
}
