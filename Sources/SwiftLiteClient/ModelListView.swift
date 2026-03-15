import SwiftUI
import SwiftLite

struct ModelListView<T: Listable>: View
{
    @Environment(Database.self) private var db
    @Environment(\.defaultEngine) private var defaultEngine
    @State private var selectedModel: T?
    @State private var newModelId: UUID?
    @LiveCollection(T.self) var snapshots

    var body: some View {
        List(selection: $selectedModel) {
            ForEach(snapshots) { snapshot in
                NavigationLink(snapshot.name) {
                    AnyView(snapshot.detailView)
                        .id(snapshot.id)
                        .task {
                            print("Loading navigationLink")
                        }
                }
                .contextMenu {
                    Button("Delete Item", systemImage: "minus") {
                        Task {
                            try await db.delete(T.self, id: snapshot.id)
                        }
                    }
                }
            }
        }
        .onChange(of: snapshots) { oldValue, newValue in
            guard let newModelId else { return }
            if let newObject = newValue.first(where: { $0.id == newModelId }) {
                selectedModel = newObject
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
            newModelId = newModel.id
        }
    }
}
