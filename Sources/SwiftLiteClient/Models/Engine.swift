import SwiftLite

@Model class Engine
{
    @Stored(defaultValue: "")
    var name: String

    @InverseRelated(\Car.engine)
    var cars
}
