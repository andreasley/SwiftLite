//import Foundation
//
//actor WebSocketSyncTransport: SyncTransport
//{
//    func sendEntries(entries: [DatabaseLogger.LogEntry]) async -> [UUID : Int64] {
//        <#code#>
//    }
//    
//    func getEntries(from index: Int64) async -> [DatabaseLogger.LogEntry] {
//        <#code#>
//    }
//    
//    func registerIndexIncreaseCallback(_ callback: @escaping IndexIncreaseHandler) {
//        <#code#>
//    }
//    
//    var status: SyncTransportStatus = .connecting
//
//    nonisolated let databaseIdentifier: String = "test"
//    
//    var syncErrors: [SyncError] = []
//    
//    var localDatabaseUrl: URL {
//        databaseFilesDirectoryUrl.appendingPathComponent("database.sqlite", isDirectory: false)
//    }
//
//    var localDatabaseLogUrl: URL {
//        databaseFilesDirectoryUrl.appendingPathComponent("database.log.sqlite", isDirectory: false)
//    }
//    
//    var databaseFilesDirectoryUrl: URL {
//        let appSupportURL = URL.applicationSupportDirectory
//        let applicationDirectory = appSupportURL.appendingPathComponent(Bundle.main.bundleIdentifier ?? "SwiftLiteWebSocketSyncTransport", isDirectory: true)
//        let databaseFilesDirectory = applicationDirectory.appendingPathComponent(databaseIdentifier, isDirectory: true)
//        return databaseFilesDirectory
//    }
//
//    func connect() async
//    {
//    }
//}
