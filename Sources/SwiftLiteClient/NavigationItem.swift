import SwiftUI

@MainActor
struct NavigationItem: Identifiable, @MainActor Hashable
{
    static func == (lhs: NavigationItem, rhs: NavigationItem) -> Bool
    {
        lhs.id == rhs.id
    }
    
    static let car = NavigationItem(model: Car.Snapshot.self)
    static let engine = NavigationItem(model: Engine.Snapshot.self)
    static let passenger = NavigationItem(model: Passenger.Snapshot.self)

    init<T>(model: T.Type) where T: Listable
    {
        self.name = String(describing: T.Model.self)
        self.listView = AnyView(T.listView)
    }
    
    let id = UUID()
    let name: String
    let listView: AnyView
    
    func hash(into hasher: inout Hasher)
    {
        hasher.combine(id)
    }
}
