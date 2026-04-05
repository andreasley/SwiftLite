import SwiftUI
import SwiftLite
import SwiftLiteTestModels

@AsyncLoadingView
struct PassengerDetailView: View
{
    @EditableObject(autosaving: false) var passenger: Passenger
    
    var body: some View {
        EmptyView()
        Form {
            TextField("Name", text: $passenger.name)
            
            Section("Cars with this passenger") {
                List(passenger.cars) { car in
                    NavigationLink(destination: CarDetailView.loading(car: car)) {
                        Text(car.name)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .toolbar {
            Spacer()
            Button("Save") {
                Task {
                    try? await passenger.save()
                }
            }
            .disabled(!passenger._hasPendingChanges)
        }
    }
}
