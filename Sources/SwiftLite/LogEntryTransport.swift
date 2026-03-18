import Foundation

public nonisolated protocol SyncTransport: Actor, Sendable
{
    var status: SyncTransportStatus { get }
    var syncErrors: [SyncError] { get }

    nonisolated var databaseIdentifier: String { get }
    var localDatabaseUrl: URL { get }
    var localDatabaseLogUrl: URL { get }

    func connect() async
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
