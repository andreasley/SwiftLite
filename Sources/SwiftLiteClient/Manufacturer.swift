import SwiftLite
import Foundation

@Model class Manufacturer
{
    @Unique
    let publicId: UUID
    
    var name: String
}
