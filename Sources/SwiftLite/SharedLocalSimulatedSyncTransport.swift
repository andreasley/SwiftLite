import Foundation

public actor SharedLocalSimulatedSyncTransport: SyncTransport
{
    public private(set) var status: SyncTransportStatus = .connecting

    public nonisolated let databaseIdentifier: String = "test"
    public nonisolated let clientIdentifier: String
    
    private var indexIncreaseCallbacks: [IndexIncreaseHandler] = []
    private var serverLogEntries: [DatabaseLogger.LogEntry] = []
    
    private var clientIndex = 1
    
    private let statusContinuation: AsyncStream<SyncTransportStatus>.Continuation
    public nonisolated let statusStream: AsyncStream<SyncTransportStatus>
    
    public init(clientIdentifier: String) {
        self.clientIdentifier = clientIdentifier
        
        var continuation: AsyncStream<SyncTransportStatus>.Continuation!
        self.statusStream = AsyncStream { continuation = $0 }
        self.statusContinuation = continuation
    }
    
    public private(set) var syncErrors: [SyncError] = []
    
    public var localDatabaseUrl: URL {
        clientIndex += 1
        return databaseFilesDirectoryUrl
            .appendingPathComponent(clientIdentifier, isDirectory: false)
            .appendingPathComponent("database\(clientIndex).sqlite", isDirectory: false)
    }

    public var localDatabaseLogUrl: URL {
        databaseFilesDirectoryUrl
            .appendingPathComponent(clientIdentifier, isDirectory: false)
            .appendingPathComponent("database\(clientIndex).log.sqlite", isDirectory: false)
    }
    
    var databaseFilesDirectoryUrl: URL {
        let appSupportURL = URL.applicationSupportDirectory
        let applicationDirectory = appSupportURL.appendingPathComponent(Bundle.main.bundleIdentifier ?? "SwiftLiteWebSocketSyncTransport", isDirectory: true)
        let databaseFilesDirectory = applicationDirectory.appendingPathComponent(databaseIdentifier, isDirectory: true)
        return databaseFilesDirectory
    }

    public func connect() async
    {
        status = .connected
        statusContinuation.yield(.connected)
    }
    
    public func sendEntries(entries: [DatabaseLogger.LogEntry]) async -> [UUID: Int64]
    {
        var updatedIndexes = [UUID: Int64]()
        var nextIndex = Int64(serverLogEntries.count + 1)
        for entry in entries {
            guard entries.contains(where: { $0.id == entry.id && $0.synchronizedIndex == nil }) else { continue }
            let entryWithIndex = DatabaseLogger.LogEntry(
                id: entry.id,
                timestamp: entry.timestamp,
                transactionId: entry.transactionId,
                operationType: entry.operationType,
                tableName: entry.tableName,
                objectId: entry.objectId,
                columnName: entry.columnName,
                newValue: entry.newValue,
                metadata: entry.metadata,
                user: entry.user,
                synchronizedIndex: nextIndex
            )
            serverLogEntries.append(entryWithIndex)
            updatedIndexes[entry.id] = Int64(nextIndex)
            nextIndex += 1
        }
        Task {
            for callback in indexIncreaseCallbacks {
                await callback(Int64(serverLogEntries.count))
            }
        }
        return updatedIndexes
    }

    public func getEntries(from index: Int64) async -> [DatabaseLogger.LogEntry]
    {
        Array(serverLogEntries.dropFirst(Int(index)))
    }

    public func registerIndexIncreaseCallback(_ callback: @escaping IndexIncreaseHandler)
    {
        indexIncreaseCallbacks.append(callback)
    }
}
