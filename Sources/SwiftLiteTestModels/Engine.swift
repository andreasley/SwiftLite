import SwiftLite
import Foundation

@Model public final class Engine
{
    public enum CylinderCount: Int, Storable, CaseIterable, Identifiable, Sendable {
        public var id: Int { rawValue }
        case unknown = 0
        case v4 = 4
        case v6 = 6
        case v8 = 8
        case v10 = 10
        case v12 = 12
        case v16 = 16
    }
    
    @Stored(defaultValue: "")
    public var name: String

    @Stored(defaultValue: CylinderCount.unknown, fallbackValue: CylinderCount.unknown)
    public var cylinders: CylinderCount

    @InverseRelated(\Car.engine)
    public var cars: RelatedCollection<Car.Snapshot>
}
