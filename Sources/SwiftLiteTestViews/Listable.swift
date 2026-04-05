import SwiftUI
import SwiftLite
import SwiftLiteTestModels

protocol Listable: ModelSnapshot where Model: ModelWithName
{
    var name: String { get }
}

extension Car.Snapshot: Listable {}
extension Engine.Snapshot: Listable {}
extension Passenger.Snapshot: Listable {}
extension Cargo.Snapshot: Listable {}

extension Car.QueryProxy: QueryProxyWithName {}
extension Engine.QueryProxy: QueryProxyWithName {}
extension Passenger.QueryProxy: QueryProxyWithName {}
extension Cargo.QueryProxy: QueryProxyWithName {}

extension Car: ModelWithName {}
extension Engine: ModelWithName {}
extension Passenger: ModelWithName {}
extension Cargo: ModelWithName {}

protocol ModelWithName: Model where QueryProxy: QueryProxyWithName
{
    var name: String { get }
}

protocol QueryProxyWithName
{
    var name: String { get }
}
