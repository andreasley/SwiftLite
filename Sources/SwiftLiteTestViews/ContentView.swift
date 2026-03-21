import SwiftUI
import SwiftLite
import SwiftLiteTestModels


public struct ContentView: View
{
    enum MainNavigationItem: Int, Hashable, CaseIterable, Identifiable {
        case car
        case engine
        case passenger
        
        var id: Int { rawValue }
        
        var name: String {
            switch self {
            case .car: return "Car"
            case .engine: return "Engine"
            case .passenger: return "Passenger"
            }
        }
    }
    
    @Environment(Database.self) var db
    @State private var selectedEntity: MainNavigationItem?
    @State private var selectedModelId: UUID?

    public init() {}
    
    public var body: some View {
        NavigationSplitView {
            List(MainNavigationItem.allCases, selection: $selectedEntity) { item in
                NavigationLink(item.name, value: item)
            }
            .overlay(alignment: .bottom) {
                StatusView()
            }
        } content: {
            if let selectedEntity {
                switch selectedEntity {
                case .car:
                    ModelListView<Car.Snapshot>(selectedModelId: $selectedModelId)
                case .engine:
                    ModelListView<Engine.Snapshot>(selectedModelId: $selectedModelId)
                case .passenger:
                    ModelListView<Passenger.Snapshot>(selectedModelId: $selectedModelId)
                }
            }
        } detail: {
            if let selectedEntity, let selectedModelId {
                Group {
                    switch selectedEntity {
                    case .car:
                        CarDetailView.loading(car: DatabaseObjectReference(id: selectedModelId, db: db))
                    case .engine:
                        EngineDetailView.loading(engine: DatabaseObjectReference(id: selectedModelId, db: db))
                    case .passenger:
                        PassengerDetailView.loading(passenger: DatabaseObjectReference(id: selectedModelId, db: db))
                    }
                }.id(selectedModelId)
            }
        }
    }
    
}



#Preview {
    ContentView()
}

