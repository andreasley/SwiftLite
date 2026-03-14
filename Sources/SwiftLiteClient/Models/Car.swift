import SwiftLite
import Foundation

@Model nonisolated final class Car
{
    var combinedName: String {
        name + "zzz"
    }

    @Stored(defaultValue: UUID())
    let publicId: UUID

    @Related
    var engine: Engine.Snapshot

    @Related(onDelete: .cascade)
    var interior: Interior?

    @RelatedMany(Passenger.self, onDelete: .cascade)
    var passengers: PassengersCollection

    @Stored(defaultValue: "asd")
    var name: String
}
