import SwiftUI
import SwiftLite
import SwiftLiteTestModels

@AsyncLoadingView
struct EngineDetailView: View
{
    @EditableObject(autosaving: false) var engine: Engine
    
    var body: some View {
        Form {
            TextField("Name", text: $engine.name)
            
            Section("Cars with this engine") {
                List(engine.cars) { car in
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
                    try? await engine.save()
                }
            }
            .disabled(!engine._hasPendingChanges)
        }
    }
}
