import SwiftUI
import SwiftLite
import SwiftLiteTestModels

struct ModelListView<T: Listable>: View
{
    @Environment(Database.self) private var db
    @Environment(\.defaultEngine) private var defaultEngine
    @Binding var selectedModel: (any ObjectReference)?
    @State private var selection: DatabaseObjectReference<T.Model>?
    @State private var searchText = ""
    @LiveCollection(T.self, sortBy: [SortDescriptor(\T.name, order: .ascending)]) var snapshots

    var isCreatable: Bool {
        T.self is (any Creatable<T.Model>.Type)
    }

    var body: some View {
        TextField("", text: $searchText, prompt: Text("Search"))
            .labelsHidden()
        List(snapshots, selection: $selection) { snapshot in
            NavigationLink(snapshot.name, value: snapshot.getObjectReference())
                .contextMenu {
                    Button("Delete Item", systemImage: "minus") {
                        Task {
                            try await db.delete(T.self, id: snapshot.id)
                        }
                    }
                }
        }
        .onChange(of: selection) { oldValue, newValue in
            selectedModel = selection
        }
        .onChange(of: searchText) { oldValue, newValue in
            filterByName(newValue)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button("New Item", systemImage: "plus") {
                    createNew()
                }.disabled(!isCreatable)
            }
        }
    }
    
    
    func createNew()
    {
        guard let CreatableType = T.self as? (any Creatable<T.Model>.Type) else { return }
        guard let defaultEngine else { return }

        Task {
            let newModel = CreatableType.create(database: db, defaultEngine: defaultEngine)
            try await newModel.save()
            selection = newModel.getObjectReference()
        }
    }
    
    func filterByName(_ name: String)
    {
        $snapshots.filter = try? #Predicate<T> { $0.name.contains(name) }.toSQL()
    }
}
