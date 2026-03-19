import SwiftUI
import SwiftLite
import SwiftLiteTestModels

protocol Listable: ModelSnapshot
{
    var name: String { get }
}

extension Car.Snapshot: Listable {}
extension Engine.Snapshot: Listable {}
extension Passenger.Snapshot: Listable {}
