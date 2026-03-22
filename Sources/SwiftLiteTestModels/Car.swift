import SwiftLite
import Foundation

@Model public nonisolated final class Car
{
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
    
    public var combinedName: String {
        name + "zzz"
    }
    
    @Stored(defaultValue: UUID.v7())
    public let publicId: UUID
    
    @Related
    public var engine: Engine.Snapshot
    
    @Related(onDelete: .cascade)
    public var interior: Interior?
    
    @RelatedMany(Passenger.self, onDelete: .cascade)
    public var passengers: RelatedCollection<Passenger>

    @RelatedMany(Cargo.self, onDelete: .cascade)
    public var cargo: RelatedCollection<Cargo>

    @Stored(defaultValue: names.randomElement() ?? "Unknown")
    public var name: String
    
    @Stored(defaultValue: 0, fallbackValue: 0)
    public var price: Decimal
}
