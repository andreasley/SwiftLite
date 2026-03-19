import SwiftUI
import SwiftLite
import SwiftLiteTestModels
import SwiftLiteTestViews

@main
struct SwiftLiteTesterLocalSyncApp: App
{
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    @State private var transport: SharedLocalSimulatedSyncTransport = SharedLocalSimulatedSyncTransport(clientIdentifier: "test")
    
    var body: some Scene {
        WindowGroup {
            MainWindow(transport: transport)
        }
    }
    
    struct MainWindow: View
    {
        let transport: SharedLocalSimulatedSyncTransport
        
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
