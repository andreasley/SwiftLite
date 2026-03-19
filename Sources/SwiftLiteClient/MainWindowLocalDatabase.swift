import SwiftUI
import SwiftLite

struct MainWindowLocalDatabase: View
{
    @State private var database: Database?
    @State private var engine: Engine.Snapshot?
    
    var body: some View {
        if let database, let engine {
            ContentView()
                .environment(database)
                .environment(\.defaultEngine, engine)
        } else {
            ProgressView("Opening database...")
                .task {
                    do {
                        let temporaryDirectory = URL.temporaryDirectory.appending(component: "SwiftLiteDevelopment", directoryHint: .isDirectory)
                        let fileUrl = temporaryDirectory.appending(component: "test2.sqlite", directoryHint: .notDirectory)

                        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
                        let db = try await Database(storage: .file(fileUrl))
                        try await db.register(models: Car.self, Engine.self, Interior.self, Passenger.self)
                        self.database = db
                        let firstEngine = try await db.get(Engine.Snapshot.self).first
                        if firstEngine == nil {
                            let newEngine = Engine(db: db)
                            newEngine.name = "V12"
                            try await newEngine.save()
                            self.engine = try await db.get(from: newEngine)
                        } else {
                            self.engine = firstEngine
                        }
                    } catch {
                        print("Failed to open database", error.localizedDescription)
                    }
                }
        }
    }
}
