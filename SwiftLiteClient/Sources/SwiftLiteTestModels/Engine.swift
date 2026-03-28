import SwiftLite
import Foundation

@Model public final class Engine
{
    @Stored(defaultValue: "")
    public var name: String

    @InverseRelated(\Car.engine)
    public var cars: RelatedCollection<Car.Snapshot>
}
