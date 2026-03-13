import SwiftLite

class Passenger
{
    @Stored(defaultValue: "")
    var name: String

    @InverseRelatedMany(\Car.passengers)
    var cars
}
