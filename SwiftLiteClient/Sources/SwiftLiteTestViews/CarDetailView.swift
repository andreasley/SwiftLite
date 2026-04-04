import SwiftUI
import SwiftLite
import SwiftLiteTestModels

@AsyncLoadingView
struct CarDetailView: View
{
    @Environment(Database.self) private var db
    @EditableObject(autosaving: true, delayBeforeSaving: .seconds(1)) var car: Car
    @LiveCollection(Engine.Snapshot.self) var engines
    @LiveCollection(Cargo.Snapshot.self) var cargos

    var body: some View {
        Form {
            TextField("Name", text: $car.name)
            TextField("Price", value: $car.price, format: .number)
            ModelPicker("Engine", items: engines, selection: $car.engine) { engine in
                Text(engine.name)
            }
            Picker("Color", selection: $car.color) {
                ForEach(Car.Color.allCases) { color in
                    Text(color.rawValue)
                        .tag(color)
                }
            }

            Section {
                List($car.otherColors) { otherColor in
                    Picker("Accessory color", selection: otherColor) {
                        ForEach(Car.Color.allCases) { color in
                            Text(color.rawValue)
                                .tag(color)
                        }
                    }
                }
            } footer: {
                Button("Add accessory color") {
                    car.otherColors.append(.blue)
                }
            }

            PassengersSection(passengers: car.passengers)
            
            Section {
                List(car.cargo, id: \.self) { cargo in
                    HStack {
                        Text(cargo.name)
                        Spacer()
                        Button("Delete") {
                            car.cargo.remove(cargo)
                        }
                    }
                }
            } footer: {
                Menu {
                    ForEach(cargos) { cargo in
                        Button(cargo.name) {
                            car.cargo.append(cargo)
                        }
                    }
                } label: {
                    Text("Add cargo")
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

    struct PassengersSection: View
    {
        @Environment(Database.self) private var db

        let passengers: RelatedCollection<Passenger>
        
        var body: some View {
            Section {
                List(passengers) { passenger in
                    HStack {
                        PassengerView(passenger: passenger)
                        Spacer()
                        Button("Delete") {
                            passengers.remove(passenger)
                        }
                    }
                }
            } footer: {
                Button("Add passenger") {
                    passengers.append(Passenger(db: db, name: Date.now.description))
                }
            }
        }
    }

}
