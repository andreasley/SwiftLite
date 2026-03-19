import Foundation

actor WebSocketSyncTransport: SyncTransport
{
    private var indexIncreaseCallback: IndexIncreaseHandler? // this needs to be called when the server informs this client that there are new entries available

    var status: SyncTransportStatus = .connecting

    nonisolated let databaseIdentifier: String = "test"
    
    var syncErrors: [SyncError] = []
    
    var localDatabaseUrl: URL {
        databaseFilesDirectoryUrl.appendingPathComponent("database.sqlite", isDirectory: false)
    }

    var localDatabaseLogUrl: URL {
        databaseFilesDirectoryUrl.appendingPathComponent("database.log.sqlite", isDirectory: false)
    }
    
    var databaseFilesDirectoryUrl: URL {
        let appSupportURL = URL.applicationSupportDirectory
        let applicationDirectory = appSupportURL.appendingPathComponent(Bundle.main.bundleIdentifier ?? "SwiftLiteWebSocketSyncTransport", isDirectory: true)
        let databaseFilesDirectory = applicationDirectory.appendingPathComponent(databaseIdentifier, isDirectory: true)
        return databaseFilesDirectory
    }

    func registerIndexIncreaseCallback(_ callback: @escaping IndexIncreaseHandler)
    {
        indexIncreaseCallback = callback
    }

    func connect() async
    {
        // TODO
    }

    func sendEntries(entries: [DatabaseLogger.LogEntry]) async -> [UUID : Int64]
    {
        // TODO
    }
    
    func getEntries(from index: Int64) async -> [DatabaseLogger.LogEntry]
    {
        // TODO
    }
}
