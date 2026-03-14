import SwiftLite
import Foundation

@Model final class Engine
{
    @Stored(defaultValue: "")
    var name: String

    @InverseRelated(\Car.engine)
    var cars: CarsCollection
}
