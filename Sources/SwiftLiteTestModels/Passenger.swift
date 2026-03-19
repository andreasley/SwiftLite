import SwiftLite
import Foundation

@Model public nonisolated final class Passenger: Fetchable
{
    @Stored(defaultValue: "")
    public var name: String

//    @Stored(defaultValue: "")
//    public var remarks: String

    @InverseRelatedMany(\Car.passengers)
    public var cars: RelatedCollection<Car.Snapshot>
}
