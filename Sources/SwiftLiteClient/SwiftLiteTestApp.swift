import SwiftUI
import SwiftLite

@main
struct SwiftLiteTestApp: App
{
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    @State private var transport: SimulatedServerSyncTransport = SimulatedServerSyncTransport(clientIdentifier: "test")

    var body: some Scene {
        WindowGroup {
            MainWindow(transport: transport)
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

extension EnvironmentValues {
    @Entry var defaultEngine: Engine.Snapshot? = nil
}
