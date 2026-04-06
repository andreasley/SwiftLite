import Foundation

public protocol SyncConnector: Actor, Sendable
{
    typealias IndexIncreaseHandler = (_ highestIndex: Int64) async -> Void
    typealias DidConnectCallback = () -> Void

    var status: SyncConnectorStatus { get }
    var errors: [SyncConnectorError] { get }
    
    nonisolated var statusStream: AsyncStream<SyncConnectorStatus> { get }
    var databaseName: String { get }

    func getDatabaseId() async throws -> UUID?
    func connect(databaseId: UUID) async throws
    func getHighestRemoteIndex() async -> Int64?
    func sendEntries(entries: [LogEntry]) async -> [UUID: Int64]
    func getEntries(from index: Int64, limit: Int64) async -> [LogEntry]
    func onHighestRemoteIndexIncrease(_ callback: @escaping IndexIncreaseHandler)
    func onDidConnectCallback(_ callback: @escaping DidConnectCallback)
}

public nonisolated enum SyncConnectorStatus: Equatable, Sendable {
    case connecting
    case offline
    case connected
    case transferring
    case error
    
    public var isConnected: Bool {
        return switch self {
        case .connected, .transferring: true
        default: false
        }
    }
}

public nonisolated struct SyncConnectorError
{
    let date: Date
    let error: Error
    
    public init(date: Date, error: Error)
    {
        self.date = date
        self.error = error
    }
}

public extension SyncConnector
{
    var isReady: Bool {
        switch status {
        case .connected:
            return true
        default:
            return false
        }
    }
}
