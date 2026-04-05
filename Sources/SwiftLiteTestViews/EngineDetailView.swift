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
            
            Picker("Cylinders", selection: $engine.cylinders) {
                ForEach(Engine.CylinderCount.allCases) { count in
                    Text(String(count.rawValue))
                        .tag(count)
                }
            }

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
