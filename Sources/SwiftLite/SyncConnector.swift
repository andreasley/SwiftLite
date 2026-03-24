import Foundation

public nonisolated protocol SyncConnector: Actor, Sendable
{
    typealias IndexIncreaseHandler = (_ highestIndex: Int64) async -> Void
    typealias DidComeOnlineHandler = () -> Void

    var status: SyncConnectorStatus { get }
    var errors: [SyncConnectorError] { get }
    
    nonisolated var statusStream: AsyncStream<SyncConnectorStatus> { get }
    nonisolated var databaseName: String { get }

    func getDatabaseId() async throws -> UUID?
    func connect(databaseId: UUID) async throws
    func getHighestRemoteIndex() async -> Int64?
    func sendEntries(entries: [SyncClient.LogEntry]) async -> [UUID: Int64]
    func getEntries(from index: Int64, limit: Int64) async -> [SyncClient.LogEntry]
    func onHighestRemoteIndexIncrease(_ callback: @escaping IndexIncreaseHandler)
    func onDidComeBackOnline(_ callback: @escaping DidComeOnlineHandler)
}

public nonisolated enum SyncConnectorStatus: Equatable, Sendable {
    case connecting
    case offline
    case connected
    case transferring
    case error
}

public nonisolated struct SyncConnectorError
{
    let date: Date
    let error: Error
}
