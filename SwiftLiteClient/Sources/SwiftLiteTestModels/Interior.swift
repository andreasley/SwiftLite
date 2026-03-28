import SwiftLite
import Foundation

@Model public final class Interior
{
    @Transient
    var blubb: Int = 0
    
    @Stored(isUnique: true)
    let name: String
}
