import Foundation
import SwiftLite
import SQLite3
import HummingbirdWebSocket
import Hummingbird

// Helper function for SQLite transient destructor
nonisolated let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Manages the server-side database that stores operation logs from multiple clients
actor ServerDatabaseManager
{
    private var databases: [String: ServerDatabase] = [:]
    private var clientConnections: [UUID: ClientConnection] = [:]
    
    private let encoder = JSONEncoder.forSwiftLiteSync
    private let decoder = JSONDecoder.forSwiftLiteSync
    
    private let dataDir: URL

    init() async throws {
        // Ensure data directory exists
        self.dataDir = URL.applicationSupportDirectory
            .appendingPathComponent("SwiftLiteWebSyncServer", isDirectory: true)
        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
    }
    
    func getHighestIndex(databaseId: String) async throws -> Int64 {
        let database = try await getOrCreateDatabase(databaseId: databaseId)
        return await database.highestIndex
    }
    
    func addClient(session: ClientSession, outbound: WebSocketOutboundWriter) {
        clientConnections[session.id] = ClientConnection(session: session, outbound: outbound)
    }
    
    func removeClient(session: ClientSession) {
        clientConnections.removeValue(forKey: session.id)
    }
    
    func broadcastIndexUpdate(databaseId: String, highestIndex: Int64, excludingSessionId: UUID?) async {
        let message = WebSocketMessage.indexUpdate(highestIndex: highestIndex)
        
        guard let messageData = try? encoder.encode(message) else {
            print("Failed to encode index update message")
            return
        }
        
        let buffer = ByteBuffer(data: messageData)
        
        // Send to all clients connected to the same database (except the sender if specified)
        for (sessionId, connection) in clientConnections {
            if connection.session.databaseId == databaseId {
                // Skip the excluded session if provided
                if let excludedId = excludingSessionId, sessionId == excludedId {
                    continue
                }
                
                Task {
                    do {
                        try await connection.outbound.write(.binary(buffer))
                        print("📤 Sent index update (\(highestIndex)) to session \(sessionId)")
                    } catch {
                        removeClient(session: connection.session)
                        print("Failed to send index update to session \(sessionId): \(error)")
                        print("Removing session \(sessionId) from client connection list")
                    }
                }
            }
        }
    }
    
    func storeEntries(entries: [SyncClient.LogEntry], databaseId: String) async throws -> [UUID: Int64] {
        let database = try await getOrCreateDatabase(databaseId: databaseId)
        return try await database.storeEntries(entries: entries)
    }
    
    func getEntries(fromIndex: Int64, databaseId: String, limit: Int64) async throws -> [SyncClient.LogEntry] {
        let database = try await getOrCreateDatabase(databaseId: databaseId)
        return try await database.getEntries(fromIndex: fromIndex, limit: limit)
    }
    
    private func getOrCreateDatabase(databaseId: String) async throws -> ServerDatabase {
        if let existing = databases[databaseId] {
            return existing
        }
        
        let newDatabase = try await ServerDatabase(dataDir: dataDir, databaseId: databaseId)
        databases[databaseId] = newDatabase
        return newDatabase
    }
}


extension ServerDatabaseManager
{
    struct ClientConnection: Sendable
    {
        let session: ClientSession
        let outbound: WebSocketOutboundWriter
    }
}
