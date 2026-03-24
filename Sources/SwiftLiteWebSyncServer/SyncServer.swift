import Foundation
import Hummingbird
import HummingbirdWebSocket
import SwiftLite

@main
struct SyncServer {
    static func main() async throws {
        let databaseManager = try await ServerDatabaseManager()
        
        let router = Router(context: BasicWebSocketRequestContext.self)
        
        let groupForDatabase = router.group(":databaseId")
        
        // WebSocket endpoint for real-time index updates
        groupForDatabase.ws("sync") { request, context in
            _ = try context.parameters.require("databaseId")
            return .upgrade([:])
        } onUpgrade: { inbound, outbound, context in
            try await handleWebSocketConnection(
                inbound: inbound,
                outbound: outbound,
                databaseManager: databaseManager
            )
        }
        
        // HTTP POST endpoint for uploading entries
        groupForDatabase.post("upload") { request, context async throws -> Response in
            let databaseId = try context.parameters.require("databaseId")
            
            // Collect all ByteBuffer chunks from the request body
            var bodyBuffer = ByteBuffer()
            for try await chunk in request.body {
                var chunk = chunk
                bodyBuffer.writeBuffer(&chunk)
            }
            
            let data = Data(buffer: bodyBuffer)
            
            let decoder = JSONDecoder.forSwiftLiteSync
            let entries = try decoder.decode([SyncClient.LogEntry].self, from: data)
            
            let mapping = try await databaseManager.storeEntries(
                entries: entries,
                databaseId: databaseId
            )
            
            let encoder = JSONEncoder.forSwiftLiteSync
            let responseData = try encoder.encode(mapping)

            Task {
                // Broadcast index update to all connected WebSocket clients
                let highestIndex = try await databaseManager.getHighestIndex(databaseId: databaseId)
                await databaseManager.broadcastIndexUpdate(
                    databaseId: databaseId,
                    highestIndex: highestIndex,
                    excludingSessionId: nil // Broadcast to all since this is HTTP
                )
            }
            
            return Response(
                status: .ok,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: ByteBuffer(data: responseData))
            )
        }
        
        // HTTP GET endpoint for highest index
        groupForDatabase.get("highestIndex") { request, context async throws -> Response in
            let databaseId = try context.parameters.require("databaseId")
            
            let highestIndex = try await databaseManager.getHighestIndex(databaseId: databaseId)
            
            let encoder = JSONEncoder.forSwiftLiteSync
            let responseData = try encoder.encode(highestIndex)
            
            return Response(
                status: .ok,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: ByteBuffer(data: responseData))
            )
        }

        // HTTP GET endpoint for downloading entries
        groupForDatabase.get("download") { request, context async throws -> Response in
            let databaseId = try context.parameters.require("databaseId")
            
            guard let fromIndexString = request.uri.queryParameters["from"], let fromIndex = Int64(fromIndexString) else {
                return Response(status: .badRequest)
            }
            
            let limit: Int64
            if let limitString = request.uri.queryParameters["limit"], let requestedLimit = Int64(limitString) {
                limit = requestedLimit
            } else {
                limit = 10_000
            }
            
            let entries = try await databaseManager.getEntries(
                fromIndex: fromIndex,
                databaseId: databaseId,
                limit: limit
            )
            
            let encoder = JSONEncoder.forSwiftLiteSync
            let responseData = try encoder.encode(entries)
            
            return Response(
                status: .ok,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: ByteBuffer(data: responseData))
            )
        }

        let httpServerConfiguration = ApplicationConfiguration(address: .hostname("0.0.0.0", port: 8080))

        let app = Application(
            router: router,
            server: .http1WebSocketUpgrade(webSocketRouter: router),
            configuration: httpServerConfiguration
        )
        
        print("🚀 Sync Server starting on http://localhost:8080")
        print("   WebSocket: /:databaseId/sync")
        print("   Upload:    POST /:databaseId/upload")
        print("   Index:     GET  /:databaseId/highestIndex")
        print("   Download:  GET  /:databaseId/download?from=index&limit=1000")
        try await app.runService()
    }
    
    static func handleWebSocketConnection(
        inbound: WebSocketInboundStream,
        outbound: WebSocketOutboundWriter,
        databaseManager: ServerDatabaseManager
    ) async throws {
        var clientSession: ClientSession?
        
        
        let encoder = JSONEncoder.forSwiftLiteSync

        // Process incoming messages
        for try await message in inbound.messages(maxSize: 10 * 1024 * 1024) {
            guard case .binary(let buffer) = message else {
                continue
            }
            
            let data = Data(buffer: buffer)
            
            do {
                let decoder = JSONDecoder.forSwiftLiteSync
                let webSocketMessage = try decoder.decode(WebSocketMessage.self, from: data)

                let response = try await processMessage(
                    webSocketMessage,
                    clientSession: &clientSession,
                    databaseManager: databaseManager,
                    outbound: outbound
                )
                
                if let response {
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
        databaseManager: ServerDatabaseManager,
        outbound: WebSocketOutboundWriter
    ) async throws -> WebSocketMessage? {
        switch message {
        case .handshake(let databaseId):
            let session = ClientSession(databaseId: databaseId)
            clientSession = session
            await databaseManager.addClient(session: session, outbound: outbound)
            let highestIndex = try await databaseManager.getHighestIndex(databaseId: databaseId)
            print("Client with session ID \(session.id.uuidString) connected; requested database ID: \(databaseId) (highest index: \(highestIndex))")
            return nil
            
        default:
            throw ServerError.unexpectedMessage
        }
    }
}

// MARK: - Supporting Types

struct ClientSession: Identifiable, Sendable {
    let id = UUID.v7()
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
