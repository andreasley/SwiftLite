import SwiftUI
import SwiftLite
import SwiftLiteTestModels

@AsyncLoadingView
struct CarDetailView: View
{
    @Environment(Database.self) private var db
    @EditableObject(autosaving: true) var car: Car
    @LiveCollection(Engine.Snapshot.self) var engines
    
    var body: some View {
        Form {
            TextField("Name", text: $car.name)
            TextField("Price", value: $car.price, format: .number)
            ModelPicker("Engine", items: engines, selection: $car.engine) { engine in
                Text(engine.name)
            }
            Section {
                List(car.passengers) { passenger in
                    HStack {
                        PassengerView(passenger: passenger)
                        Spacer()
                        Button("Delete") {
                            car.passengers.remove(passenger)
                        }
                    }
                }
            } footer: {
                Button("Add passenger") {
                    car.passengers.append(Passenger(db: db, name: Date.now.description))
                }
            }
            Section {
                List(car.cargo) { cargo in
                    HStack {
                        CargoView(cargo: cargo)
                        Spacer()
                        Button("Delete") {
                            car.cargo.remove(cargo)
                        }
                    }
                }
            } footer: {
                Button("Add cargo") {
                    car.cargo.append(Cargo(db: db, name: "Stuff"))
                }
            }
        }
        .formStyle(.grouped)
    }
    
    struct PassengerView: View
    {
        @State var passenger: Passenger
        
        var body: some View {
            TextField("Name", text: $passenger.name)
        }
    }

    struct CargoView: View
    {
        @State var cargo: Cargo
        
        var body: some View {
            TextField("Name", text: $cargo.name)
        }
    }

}
