import Foundation

public nonisolated protocol Fetchable: Hashable, Identifiable, InitializableFromResultRowAsync, SQLValueConvertible, DatabaseEntityReferenceConvertible, Saveable, SendableMetatype where Model: SwiftLite.Model
{
    associatedtype Model
    var id: UUID { get }
    var _hasPendingChanges: Bool { get }
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
