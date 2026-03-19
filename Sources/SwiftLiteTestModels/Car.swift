import SwiftLite
import Foundation

@Model public nonisolated final class Car
{
    public var combinedName: String {
        name + "zzz"
    }
    
    @Stored(defaultValue: UUID())
    public let publicId: UUID
    
    @Related
    public var engine: Engine.Snapshot
    
    @Related(onDelete: .cascade)
    public var interior: Interior?
    
    @RelatedMany(Passenger.self, onDelete: .cascade)
    public var passengers: RelatedCollection<Passenger>

    @RelatedMany(Cargo.self, onDelete: .cascade)
    public var cargo: RelatedCollection<Cargo>

    @Stored(defaultValue: "asd")
    public var name: String
    
    @Stored(defaultValue: 0, fallbackValue: 0)
    public var price: Decimal
}
