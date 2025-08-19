import SwiftLite
import Foundation

@Model class Manufacturer
{
//    @Attribute(.readOnly, .unique)
    var publicId: UUID = UUID()
    
    var name: String
}
