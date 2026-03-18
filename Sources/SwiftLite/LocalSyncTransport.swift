import Foundation

actor SimulatedServerSyncTransport: SyncTransport
{
    private(set) var status: SyncTransportStatus = .connecting

    nonisolated let databaseIdentifier: String = "test"
    nonisolated let clientIdentifier: String
    
    private var indexIncreaseCallbacks: [IndexIncreaseHandler] = []
    private var serverLogEntries: [DatabaseLogger.LogEntry] = []
    
    init(clientIdentifier: String) {
        self.clientIdentifier = clientIdentifier
    }
    
    private(set) var syncErrors: [SyncError] = []
    
    var simulatedServerDatabaseUrl: URL {
        databaseFilesDirectoryUrl.appendingPathComponent("server.sqlite", isDirectory: false)
    }

    var localDatabaseUrl: URL {
        databaseFilesDirectoryUrl
            .appendingPathComponent(clientIdentifier, isDirectory: false)
            .appendingPathComponent("database.sqlite", isDirectory: false)
    }

    var localDatabaseLogUrl: URL {
        databaseFilesDirectoryUrl
            .appendingPathComponent(clientIdentifier, isDirectory: false)
            .appendingPathComponent("database.log.sqlite", isDirectory: false)
    }
    
    var databaseFilesDirectoryUrl: URL {
        let appSupportURL = URL.applicationSupportDirectory
        let applicationDirectory = appSupportURL.appendingPathComponent(Bundle.main.bundleIdentifier ?? "SwiftLiteWebSocketSyncTransport", isDirectory: true)
        let databaseFilesDirectory = applicationDirectory.appendingPathComponent(databaseIdentifier, isDirectory: true)
        return databaseFilesDirectory
    }

    func connect() async
    {
        status = .connected
    }
    
    func sendEntries(entries: [DatabaseLogger.LogEntry]) async -> [UUID: Int64]
    {
        var updatedIndexes = [UUID: Int64]()
        for entry in entries {
            serverLogEntries.append(entry)
            updatedIndexes[entry.id] = Int64(serverLogEntries.count)
        }
        for callback in indexIncreaseCallbacks {
            callback(Int64(serverLogEntries.count))
        }
        return updatedIndexes
    }

    func getEntries(from index: Int64) async -> [DatabaseLogger.LogEntry]
    {
        Array(serverLogEntries.dropFirst(Int(index)))
    }

    func registerIndexIncreaseCallback(_ callback: @escaping IndexIncreaseHandler)
    {
        indexIncreaseCallbacks.append(callback)
    }
}
