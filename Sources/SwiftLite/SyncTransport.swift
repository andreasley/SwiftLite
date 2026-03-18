import Foundation

actor WebSocketSyncTransport: SyncTransport
{
    var status: SyncTransportStatus = .connecting

    nonisolated let databaseIdentifier: String = "test"
    
    var syncErrors: [SyncError] = []
    
    var localDatabaseUrl: URL {
        databaseFilesDirectoryUrl.appendingPathComponent("database.sqlite", isDirectory: false)
    }

    var localDatabaseLogUrl: URL {
        databaseFilesDirectoryUrl.appendingPathComponent("database.sqlite", isDirectory: false)
    }
    
    var databaseFilesDirectoryUrl: URL {
        let appSupportURL = URL.applicationSupportDirectory
        let applicationDirectory = appSupportURL.appendingPathComponent(Bundle.main.bundleIdentifier ?? "SwiftLiteWebSocketSyncTransport", isDirectory: true)
        let databaseFilesDirectory = applicationDirectory.appendingPathComponent(databaseIdentifier, isDirectory: true)
        return databaseFilesDirectory
    }

    func connect() async
    {
    }
}
