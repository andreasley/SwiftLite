import SwiftUI
import SwiftLite


struct ContentView: View
{
    @Environment(Database.self) var db
    @State private var selectedEntity: NavigationItem?
    @State private var selectedModel: (any Fetchable)?
    

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedEntity) {
                ForEach([NavigationItem.car, NavigationItem.engine, NavigationItem.passenger]) { item in
                    NavigationLink(item.name, destination: item.listView)
                }
            }
        } content: {
            EmptyView()
        } detail: {
            EmptyView()
        }
    }
}



#Preview {
    ContentView()
}

