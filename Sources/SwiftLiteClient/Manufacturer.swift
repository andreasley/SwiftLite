import SwiftLite
import Foundation

@Model final class Manufacturer
{
    @Unique
    let publicId: UUID
    
    var name: String
}
