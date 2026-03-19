import SwiftUI
import SwiftLite
import SwiftLiteTestModels
import SwiftLiteTestViews

@main
struct SwiftLiteTesterWebSocketSyncApp: App
{
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    @State private var transport: WebSocketSyncTransport = WebSocketSyncTransport(serverURL: URL(string: "ws://localhost:8888")!)
    @State private var database: Database?
    @State private var engine: Engine.Snapshot?
    @State private var databaseOpenError: Error?

    var body: some Scene {
        WindowGroup {
            if let database, let engine {
                ContentView()
                    .environment(database)
                    .environment(\.defaultEngine, engine)
            } else if let databaseOpenError {
                ContentUnavailableView("Failed to open database", systemImage: "externaldrive.badge.xmark", description: Text(databaseOpenError.localizedDescription))
            } else {
                ProgressView("Opening database...")
                    .task {
                        do {
                            let db = try await Database(storage: .distributed(transport))
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
                            self.databaseOpenError = error
                            print("Failed to open database", error.localizedDescription)
                        }
                    }
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate
{
    func applicationDidFinishLaunching(_ notification: Notification)
    {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
