import SwiftLite
import Foundation

@Model(withLifecycleFunctions: true) public nonisolated final class Car
{
    public enum Color: String, Storable, CaseIterable, Codable, Sendable, Identifiable {
        public var id: RawValue { self.rawValue }
        case red
        case blue
        case silver
        case black
    }
    
    static let names = [
        "Toyota Corolla",
        "Toyota Camry",
        "Honda Civic",
        "Honda Accord",
        "Volkswagen Golf",
        "Volkswagen Passat",
        "Toyota RAV4",
        "Honda CR-V",
        "Nissan Rogue",
        "Hyundai Tucson",
        "Kia Sportage",
        "Ford Explorer",
        "Ford F-150",
        "Chevrolet Silverado",
        "Ram 1500",
        "Tesla Model 3",
        "Tesla Model Y",
        "BYD Qin",
        "BMW 3 Series",
        "Mercedes-Benz C-Class",
    ]
    
    @SnapshotCompatible
    public var combinedName: String {
        name + "zzz"
    }
    
    @Transient
    public var dontStore = "asd"
    
    @Stored
    public let owner: String?
    
    @Stored(defaultValue: UUID.v7())
    public let publicId: UUID

    @Stored(fallbackValue: Color.red)
    public var color: Color

    @Stored(defaultValue: [], fallbackValue: [])
    public var otherColors: [Color]

    @Related
    public var successorTo: Car?

    @Related
    @SnapshotPrefetched
    public var engine: Engine.Snapshot
    
    @Related(onDelete: .cascade)
    public let interior: Interior?
    
    @RelatedMany(Passenger.self, onDelete: .cascade)
    public var passengers: RelatedCollection<Passenger>

    @SnapshotPrefetched
    @RelatedMany(Cargo.self, onDelete: .cascade)
    public var cargo: RelatedCollection<Cargo>

    @Stored(defaultValue: names.randomElement() ?? "Unknown")
    public var name: String
    
    @Stored(defaultValue: 0, fallbackValue: 0)
    public var price: Decimal
    
    public func afterInit() {
        print("after init")
    }
    
    public nonisolated(nonsending) func beforeSave() async throws {
        print("before save; could even do async verification and throw to cancel saving")
    }
    public func afterSave() {
        print("after save")
    }
}
