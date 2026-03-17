import SwiftLite
import Foundation

@Model nonisolated final class Passenger: Fetchable
{
    @Stored(defaultValue: "")
    var name: String

//    @Stored(defaultValue: "")
//    var remarks: String

    @InverseRelatedMany(\Car.passengers)
    var cars: RelatedCollection<Car.Snapshot>
}
