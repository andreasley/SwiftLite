import Foundation

public nonisolated protocol SyncTransport: Actor, Sendable
{
    typealias IndexIncreaseHandler = (_ highestIndex: Int64) -> Void

    var status: SyncTransportStatus { get }
    var syncErrors: [SyncError] { get }

    nonisolated var databaseIdentifier: String { get }
    var localDatabaseUrl: URL { get }
    var localDatabaseLogUrl: URL { get }

    func connect() async
    func sendEntries(entries: [DatabaseLogger.LogEntry]) async -> [UUID: Int64]
    func getEntries(from index: Int64) async -> [DatabaseLogger.LogEntry]
    func registerIndexIncreaseCallback(_ callback: @escaping IndexIncreaseHandler)
}

public nonisolated enum SyncTransportStatus: Equatable, Sendable {
    case connecting
    case offline
    case accessDenied
    case syncing(download: Progress, upload: Progress)
    case connected
}

public nonisolated struct SyncError
{
    let date: Date
    let error: Error
}
