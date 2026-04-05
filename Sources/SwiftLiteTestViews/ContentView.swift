import SwiftUI
import SwiftLite
import SwiftLiteTestModels


public struct ContentView: View
{
    enum MainNavigationItem: Int, Hashable, CaseIterable, Identifiable {
        case car
        case engine
        case passenger
        case cargo

        var id: Int { rawValue }
        
        var name: String {
            switch self {
            case .car: return "Car"
            case .engine: return "Engine"
            case .passenger: return "Passenger"
            case .cargo: return "Cargo"
            }
        }
    }
    
    @Environment(Database.self) var db
    @State private var selectedEntity: MainNavigationItem?
    @State private var selectedModel: (any ObjectReference)?

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
                    ModelListView<Car.Snapshot>(selectedModel: $selectedModel)
                case .engine:
                    ModelListView<Engine.Snapshot>(selectedModel: $selectedModel)
                case .passenger:
                    ModelListView<Passenger.Snapshot>(selectedModel: $selectedModel)
                case .cargo:
                    ModelListView<Cargo.Snapshot>(selectedModel: $selectedModel)
                }
            }
        } detail: {
            if let selectedModel {
                Group {
                    switch selectedModel {
                    case let selectedCar as DatabaseObjectReference<Car>:
                        CarDetailView.loading(car: selectedCar)
                    case let selectedEngine as DatabaseObjectReference<Engine>:
                        EngineDetailView.loading(engine: selectedEngine)
                    case let selectedPassenger as DatabaseObjectReference<Passenger>:
                        PassengerDetailView.loading(passenger: selectedPassenger)
                    case let selectedCargo as DatabaseObjectReference<Cargo>:
                        CargoDetailView.loading(cargo: selectedCargo)
                    default:
                        ContentUnavailableView("Not implemented", systemImage: "questionmark.square.dashed")
                    }
                }.id(selectedModel.id)
            }
        }
    }
    
}



#Preview {
    ContentView()
}

