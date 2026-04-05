import SwiftUI
import SwiftLite
import SwiftLiteTestModels

@AsyncLoadingView
struct CargoDetailView: View
{
    @EditableObject var cargo: Cargo
    
    var body: some View {
        Form {
            TextField("Name", text: $cargo.name)
        }
        .formStyle(.grouped)
    }
}
