import SwiftLite
import Foundation

@Model public final class Cargo
{
    @Stored(defaultValue: "")
    public var name: String
}
