import SwiftUI
import SwiftLite

@MainActor
protocol Listable: ModelSnapshot
{
    var name: String { get }
    var detailView: any View { get }
}

extension Listable
{
    static var listView: any View
    {
        ModelListView<Self>()
    }
}

@MainActor
extension Car.Snapshot: Listable
{
    var detailView: any View {
        CarDetailView.loading(car: self)
    }
}

@MainActor
extension Engine.Snapshot: Listable
{
    var detailView: any View {
        EngineDetailView.loading(engine: self)
    }
}

@MainActor
extension Passenger.Snapshot: Listable
{
    var detailView: any View {
        PassengerDetailView.loading(passenger: self)
    }
}

