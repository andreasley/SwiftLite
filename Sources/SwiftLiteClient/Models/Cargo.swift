import SwiftLite
import Foundation

@Model final class Cargo
{
    @Stored(defaultValue: "")
    var name: String
}
