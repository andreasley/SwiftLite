import SwiftUI
import SwiftLite

struct ModelListView<T: Listable>: View
{
    @Environment(Database.self) private var db
    @Environment(\.defaultEngine) private var defaultEngine
    @Binding var selectedModelId: T.ID?
    @LiveCollection(T.self) var snapshots
    
    var body: some View {
        List(snapshots, selection: $selectedModelId) { snapshot in
            NavigationLink(snapshot.name, value: snapshot)
                .contextMenu {
                    Button("Delete Item", systemImage: "minus") {
                        Task {
                            try await db.delete(T.self, id: snapshot.id)
                        }
                    }
                }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                if let CreatableType = T.self as? (any Creatable.Type) {
                    Button("New Item", systemImage: "plus") {
                        guard let defaultEngine else { return }
                        createNew(CreatableType.self, defaultEngine: defaultEngine)
                    }
                }
            }
        }
    }
    
    func createNew<C: Creatable>(_ type: C.Type = C.self, defaultEngine: Engine.Snapshot)
    {
        Task {
            let newModel = C.create(database: db, defaultEngine: defaultEngine)
            try await newModel.save()
            selectedModelId = newModel.id
        }
    }
}
