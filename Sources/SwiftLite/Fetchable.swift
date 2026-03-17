import Foundation

public nonisolated protocol Fetchable: Hashable, Identifiable, InitializableFromResultRowAsync, SQLValueConvertible, Saveable, DatabaseObjectReferenceConvertible, SendableMetatype where Model: SwiftLite.Model, ID == UUID
{
    associatedtype Model
    associatedtype Metadata: DatabaseEntityMetadata

    var id: ID { get }
    var _hasPendingChanges: Bool { get }
    var _metadata: Metadata { get }
}

public nonisolated extension Fetchable
{
    static func == (lhs: Self, rhs: Self) -> Bool
    {
        // Compare both id and last read date to ensure SwiftUI (e.g. `ForEach`) picks up on property updates
        lhs.id == rhs.id && lhs._metadata.lastRead == rhs._metadata.lastRead
    }
    
    func hash(into hasher: inout Hasher)
    {
        hasher.combine(id)
        hasher.combine(_metadata.lastRead)
    }
}
