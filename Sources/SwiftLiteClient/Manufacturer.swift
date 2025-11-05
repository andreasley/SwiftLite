import SwiftLite
import Foundation

@Model final class Manufacturer
{
    @Stored(defaultValue: UUID(), isUnique: true)
    let publicId: UUID

    var name: String
}
