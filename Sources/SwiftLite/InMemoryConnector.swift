import Foundation

public actor InMemoryConnector: SyncConnector
{
    public private(set) var status: SyncConnectorStatus = .connecting
    
    public nonisolated let databaseIdentifier: String = "test"
    public nonisolated let clientIdentifier: String
    
    private var indexIncreaseCallbacks: [IndexIncreaseHandler] = []
    private var serverLogEntries: [SyncClient.LogEntry] = []
    
    private var clientIndex = 1
    
    private let statusContinuation: AsyncStream<SyncConnectorStatus>.Continuation
    public nonisolated let statusStream: AsyncStream<SyncConnectorStatus>
    
    public init(clientIdentifier: String) {
        self.clientIdentifier = clientIdentifier
        
        var continuation: AsyncStream<SyncConnectorStatus>.Continuation!
        self.statusStream = AsyncStream { continuation = $0 }
        self.statusContinuation = continuation
    }
    
    public private(set) var errors: [SyncConnectorError] = []
    
    public func connect() async
    {
        status = .connected
        statusContinuation.yield(.connected)
    }
    
    public func getHighestRemoteIndex() async -> Int64?
    {
        Int64(serverLogEntries.count)
    }
    
    public func sendEntries(entries: [SyncClient.LogEntry]) async -> [UUID: Int64]
    {
        var updatedIndexes = [UUID: Int64]()
        var nextIndex = Int64(serverLogEntries.count + 1)
        for entry in entries {
            guard entries.contains(where: { $0.id == entry.id && $0.synchronizedIndex == nil }) else { continue }
            let entryWithIndex = SyncClient.LogEntry(
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
    
    public func getEntries(from index: Int64, limit: Int64) async -> [SyncClient.LogEntry]
    {
        Array(serverLogEntries.dropFirst(Int(index)))
    }
    
    public func onHighestRemoteIndexIncrease(_ callback: @escaping IndexIncreaseHandler)
    {
        indexIncreaseCallbacks.append(callback)
    }
    
    public func onDidComeBackOnline(_ callback: @escaping DidComeOnlineHandler) {}
}
