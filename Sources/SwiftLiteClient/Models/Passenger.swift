import SwiftLite

@Model nonisolated final class Passenger
{
    @Stored(defaultValue: "")
    var name: String

    @InverseRelatedMany(\Car.passengers)
    var cars: AnyRandomAccessCollection<Car>
}
