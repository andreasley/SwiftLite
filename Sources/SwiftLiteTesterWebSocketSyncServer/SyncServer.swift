import Foundation
import Hummingbird
import HummingbirdWebSocket
import SwiftLite

@main
struct SyncServer {
    static func main() async throws {
        let databaseManager = try await ServerDatabaseManager()
        
        let router = Router(context: BasicWebSocketRequestContext.self)
        router.ws("/sync") { request, context in
            return .upgrade([:])
        } onUpgrade: { inbound, outbound, context in
            try await handleWebSocketConnection(
                inbound: inbound,
                outbound: outbound,
                databaseManager: databaseManager
            )
        }
        
        let httpServerConfiguration = ApplicationConfiguration(address: .hostname("0.0.0.0", port: 8080))

        let app = Application(
            router: router,
            server: .http1WebSocketUpgrade(webSocketRouter: router),
            configuration: httpServerConfiguration
        )
        
        print("🚀 WebSocket Sync Server starting on ws://localhost:8080/sync")
        try await app.runService()
    }
    
    static func handleWebSocketConnection(
        inbound: WebSocketInboundStream,
        outbound: WebSocketOutboundWriter,
        databaseManager: ServerDatabaseManager
    ) async throws {
        var clientSession: ClientSession?
        
        // Process incoming messages
        for try await message in inbound.messages(maxSize: 10 * 1024 * 1024) {
            guard case .binary(let buffer) = message else {
                continue
            }
            
            let data = Data(buffer: buffer)
            
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let webSocketMessage = try decoder.decode(WebSocketMessage.self, from: data)

                let response = try await processMessage(
                    webSocketMessage,
                    clientSession: &clientSession,
                    databaseManager: databaseManager
                )
                
                if let response {
                    let encoder = JSONEncoder()
                    encoder.dateEncodingStrategy = .iso8601
                    let responseData = try encoder.encode(response)
                    try await outbound.write(.binary(ByteBuffer(data: responseData)))
                }
            } catch {
                print("Error processing message: \(error)")
                let errorMessage = WebSocketMessage.error(message: error.localizedDescription)
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let errorData = try encoder.encode(errorMessage)
                try await outbound.write(.binary(ByteBuffer(data: errorData)))
            }
        }
        
        // Clean up when connection closes
        if let session = clientSession {
            await databaseManager.removeClient(session: session)
        }
    }
    
    static func processMessage(
        _ message: WebSocketMessage,
        clientSession: inout ClientSession?,
        databaseManager: ServerDatabaseManager
    ) async throws -> WebSocketMessage? {
        switch message {
        case .handshake(let databaseId):
            let session = ClientSession(databaseId: databaseId)
            clientSession = session
            await databaseManager.addClient(session: session)
            let highestIndex = try await databaseManager.getHighestIndex(databaseId: databaseId)
            print("Client with session ID \(session.id.uuidString) connected; requested database ID: \(databaseId) (highest index: \(highestIndex))")
            return nil
            
        case .uploadEntries(let entries):
            guard let session = clientSession else {
                throw ServerError.notAuthenticated
            }
            
            let mapping = try await databaseManager.storeEntries(
                entries: entries,
                databaseId: session.databaseId
            )
            
            Task {
                // TODO: Inform all other WebSockets that are working with the same databaseId about the new highestIndex
            }
            
            return .uploadResponse(mapping: mapping)
            
        case .downloadEntries(let fromIndex):
            guard let session = clientSession else {
                throw ServerError.notAuthenticated
            }
            
            let entries = try await databaseManager.getEntries(
                fromIndex: fromIndex,
                databaseId: session.databaseId
            )
            return .downloadResponse(entries: entries)
            
        default:
            throw ServerError.unexpectedMessage
        }
    }
}

// MARK: - Supporting Types

struct ClientSession: Identifiable, Sendable {
    let id = UUID()
    let databaseId: String
}

enum ServerError: LocalizedError {
    case notAuthenticated
    case unexpectedMessage
    case databaseError(String)
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Client must send handshake first"
        case .unexpectedMessage:
            return "Received unexpected message type"
        case .databaseError(let message):
            return "Database error: \(message)"
        }
    }
}
