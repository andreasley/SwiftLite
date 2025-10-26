import SwiftLite
import Foundation
import Observation

@Observable @Model final class Car
{
    static let customIndexes = [
        CompositeIndex<Car>(columns: ["name": \.name, "year": \.year])
    ]
        
    @Stored(defaultValue: UUID(), isUnique: true, isIndexed: true)
    let publicId: UUID
    
    var name: String
    
    var year: Int
    
    @Related
    var manufacturer: Manufacturer?

    var röt: String?
    
    @Stored(defaultValue: 0.1)
    var 😗: Decimal

    convenience init(name: String)
    {
        self.init(name: name, year: 2025)
    }
}

