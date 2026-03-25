import SwiftUI
import SwiftLite
import SwiftLiteTestModels
import SwiftLiteTestViews

@main
struct SwiftLiteWebSyncTesterApp: App
{
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    @State private var database: Database?
    @State private var engine: Engine.Snapshot?
    @State private var databaseOpenError: Error?
    @AppStorage("server") private var server: String = "localhost:8080"
    @State private var databaseName: String = "test"
    @State private var hasValidServer: Bool = false

    
    var body: some Scene {
        WindowGroup {
            if let database, let engine {
                ContentView()
                    .environment(database)
                    .environment(\.defaultEngine, engine)
            } else if let databaseOpenError {
                ContentUnavailableView("Failed to open database", systemImage: "externaldrive.badge.xmark", description: Text(databaseOpenError.localizedDescription))
                Button("Reset") {
                    self.databaseOpenError = nil
                }
            } else if let database {
                ProgressView("Opening database...")
                    .task {
                        do {
                            await database.syncClient?.sync()
                            try await database.register(models: Car.self, Engine.self, Interior.self, Passenger.self)
                            let firstEngine = try await database.get(Engine.Snapshot.self).first
                            if firstEngine == nil {
                                let newEngine = Engine(db: database)
                                newEngine.name = "V12"
                                try await newEngine.save()
                                self.engine = try await database.get(from: newEngine)
                            } else {
                                self.engine = firstEngine
                            }
                        } catch {
                            self.databaseOpenError = error
                            print("Failed to register models and start sync", error.localizedDescription)
                        }
                    }
                SwiftLiteTestViews.StatusView()
                    .environment(database)
            } else {
                Form {
                    Section {
                        TextField("URL", text: $server)
                        TextField("Database name", text: $databaseName)
                    } footer: {
                        Button("Connect") {
                            Task {
                                do {
                                    let databaseDirectory = URL.databaseFilesDirectory(for: databaseName)
                                    let databaseFile = databaseDirectory.appendingPathComponent("database.sqlite", isDirectory: false)
                                    let connector = WebSyncConnector(server: server, databaseName: databaseName)
                                    let db = try await Database(storage: .file(databaseFile), sync: .enabled(using: connector))
                                    self.database = db
                                } catch {
                                    self.databaseOpenError = error
                                    print("Failed to open database", error.localizedDescription)
                                }
                            }
                        }
                        .disabled(!hasValidServer)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .formStyle(.grouped)
                .onAppear(perform: checkServer)
                .onChange(of: server) { _, _ in
                    checkServer()
                }
            }
        }
    }
    
    func checkServer()
    {
        self.hasValidServer = URL(string: "http://\(server)/") != nil
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
