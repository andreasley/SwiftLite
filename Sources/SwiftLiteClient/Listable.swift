import SwiftUI
import SwiftLite

protocol Listable: ModelSnapshot
{
    var name: String { get }
}

extension Car.Snapshot: Listable {}
extension Engine.Snapshot: Listable {}
extension Passenger.Snapshot: Listable {}
