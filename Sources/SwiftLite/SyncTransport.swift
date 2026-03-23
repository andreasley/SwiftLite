import Foundation

public nonisolated protocol SyncTransport: Actor, Sendable
{
    typealias IndexIncreaseHandler = (_ highestIndex: Int64) async -> Void
    typealias DidComeOnlineHandler = () -> Void

    var status: TransportStatus { get }
    var syncErrors: [SyncError] { get }
    
    nonisolated var statusStream: AsyncStream<TransportStatus> { get }

    nonisolated var databaseIdentifier: String { get }
    var localDatabaseUrl: URL { get }
    var localDatabaseLogUrl: URL { get }

    func connect() async
    func getHighestRemoteIndex() async -> Int64?
    func sendEntries(entries: [DatabaseLogger.LogEntry]) async -> [UUID: Int64]
    func getEntries(from index: Int64, limit: Int64) async -> [DatabaseLogger.LogEntry]
    func onHighestRemoteIndexIncrease(_ callback: @escaping IndexIncreaseHandler)
    func onDidComeBackOnline(_ callback: @escaping DidComeOnlineHandler)
}

public nonisolated enum TransportStatus: Equatable, Sendable {
    case connecting
    case offline
    case connected
    case transferring
    case error
}

public nonisolated struct SyncError
{
    let date: Date
    let error: Error
}
