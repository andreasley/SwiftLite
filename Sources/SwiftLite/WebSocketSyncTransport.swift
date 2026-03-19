import Foundation

public actor WebSocketSyncTransport: SyncTransport
{
    // MARK: - Properties
    
    private var indexIncreaseCallback: IndexIncreaseHandler? // this needs to be called when the server informs this client that there are new entries available

    public private(set) var status: SyncTransportStatus = .connecting

    public nonisolated let databaseIdentifier: String
    
    public private(set) var syncErrors: [SyncError] = []
    
    private var webSocketTask: URLSessionWebSocketTask?
    private let serverURL: URL
    private let session: URLSession
    private var reconnectTask: Task<Void, Never>?
    
    // MARK: - Database URLs
    
    public var localDatabaseUrl: URL {
        databaseFilesDirectoryUrl.appendingPathComponent("database.sqlite", isDirectory: false)
    }

    public var localDatabaseLogUrl: URL {
        databaseFilesDirectoryUrl.appendingPathComponent("database.log.sqlite", isDirectory: false)
    }
    
    public var databaseFilesDirectoryUrl: URL {
        let appSupportURL = URL.applicationSupportDirectory
        let applicationDirectory = appSupportURL.appendingPathComponent(Bundle.main.bundleIdentifier ?? "SwiftLiteWebSocketSyncTransport", isDirectory: true)
        let databaseFilesDirectory = applicationDirectory.appendingPathComponent(databaseIdentifier, isDirectory: true)
        return databaseFilesDirectory
    }
    
    // MARK: - Initialization
    
    public init(serverURL: URL, databaseIdentifier: String = "test", session: URLSession = .shared)
    {
        self.serverURL = serverURL
        self.databaseIdentifier = databaseIdentifier
        self.session = session
    }
    
    deinit
    {
        reconnectTask?.cancel()
    }

    // MARK: - SyncTransport Protocol

    public func registerIndexIncreaseCallback(_ callback: @escaping IndexIncreaseHandler)
    {
        indexIncreaseCallback = callback
    }

    public func connect() async
    {
        status = .connecting
        
        // Create WebSocket task
        webSocketTask = session.webSocketTask(with: serverURL)
        webSocketTask?.resume()
        
        // Send initial handshake
        do {
            let handshake = WebSocketMessage.handshake(databaseId: databaseIdentifier)
            try await send(message: handshake)
            status = .connected
        } catch {
            status = .offline
            addError(error)
            await scheduleReconnect()
        }
    }

    public func sendEntries(entries: [DatabaseLogger.LogEntry]) async -> [UUID : Int64]
    {
        guard webSocketTask != nil else {
            addError(WebSocketError.notConnected)
            return [:]
        }
        
        do {
            // Send entries to server
            let message = WebSocketMessage.uploadEntries(entries: entries)
            try await send(message: message)
            
            // Wait for response
            let response = try await receiveMessage()
            
            switch response {
            case .uploadResponse(let mapping):
                return mapping
            case .error(let errorMessage):
                addError(WebSocketError.serverError(errorMessage))
                return [:]
            default:
                addError(WebSocketError.unexpectedResponse)
                return [:]
            }
        } catch {
            status = .offline
            addError(error)
            await scheduleReconnect()
            return [:]
        }
    }
    
    public func getEntries(from index: Int64) async -> [DatabaseLogger.LogEntry]
    {
        guard webSocketTask != nil else {
            addError(WebSocketError.notConnected)
            return []
        }
        
        do {
            // Request entries from server
            let message = WebSocketMessage.downloadEntries(fromIndex: index)
            try await send(message: message)
            
            // Wait for response
            let response = try await receiveMessage()
            
            switch response {
            case .downloadResponse(let entries):
                return entries
            case .error(let errorMessage):
                addError(WebSocketError.serverError(errorMessage))
                return []
            default:
                addError(WebSocketError.unexpectedResponse)
                return []
            }
        } catch {
            status = .offline
            addError(error)
            await scheduleReconnect()
            return []
        }
    }
    
    // MARK: - Private Methods
    
    private func handleIncomingMessage(_ message: URLSessionWebSocketTask.Message) async {
        do {
            let webSocketMessage = try parseMessage(message)
            
            switch webSocketMessage {
            case .indexUpdate(let highestIndex):
                // Notify that new entries are available
                if let callback = indexIncreaseCallback {
                    await callback(highestIndex)
                }
            case .error(let errorMessage):
                addError(WebSocketError.serverError(errorMessage))
            default:
                // Other messages are handled by explicit receive calls
                break
            }
        } catch {
            addError(error)
        }
    }
    
    private func send(message: WebSocketMessage) async throws {
        guard let webSocketTask = webSocketTask else {
            throw WebSocketError.notConnected
        }
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(message)
        
        let urlMessage = URLSessionWebSocketTask.Message.data(data)
        try await webSocketTask.send(urlMessage)
    }
    
    private func receiveMessage() async throws -> WebSocketMessage {
        guard let webSocketTask = webSocketTask else {
            throw WebSocketError.notConnected
        }
        
        let message = try await webSocketTask.receive()
        return try parseMessage(message)
    }
    
    private func parseMessage(_ message: URLSessionWebSocketTask.Message) throws -> WebSocketMessage {
        let data: Data
        
        switch message {
        case .data(let messageData):
            data = messageData
        case .string(let text):
            guard let textData = text.data(using: .utf8) else {
                throw WebSocketError.invalidMessage
            }
            data = textData
        @unknown default:
            throw WebSocketError.invalidMessage
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(WebSocketMessage.self, from: data)
    }
    
    private func scheduleReconnect() async {
        reconnectTask?.cancel()
        
        reconnectTask = Task {
            try? await Task.sleep(for: .seconds(5))
            
            if !Task.isCancelled {
                await connect()
            }
        }
    }
    
    private func addError(_ error: Error) {
        let syncError = SyncError(date: Date(), error: error)
        syncErrors.append(syncError)
        
        // Keep only the last 100 errors
        if syncErrors.count > 100 {
            syncErrors.removeFirst(syncErrors.count - 100)
        }
    }
}
// MARK: - WebSocket Message Types

private enum WebSocketMessage: Codable {
    case handshake(databaseId: String)
    case uploadEntries(entries: [DatabaseLogger.LogEntry])
    case uploadResponse(mapping: [UUID: Int64])
    case downloadEntries(fromIndex: Int64)
    case downloadResponse(entries: [DatabaseLogger.LogEntry])
    case indexUpdate(highestIndex: Int64)
    case error(message: String)
    
    enum CodingKeys: String, CodingKey {
        case type
        case databaseId
        case entries
        case mapping
        case fromIndex
        case highestIndex
        case message
    }
    
    enum MessageType: String, Codable {
        case handshake
        case uploadEntries
        case uploadResponse
        case downloadEntries
        case downloadResponse
        case indexUpdate
        case error
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(MessageType.self, forKey: .type)
        
        switch type {
        case .handshake:
            let databaseId = try container.decode(String.self, forKey: .databaseId)
            self = .handshake(databaseId: databaseId)
        case .uploadEntries:
            let entries = try container.decode([DatabaseLogger.LogEntry].self, forKey: .entries)
            self = .uploadEntries(entries: entries)
        case .uploadResponse:
            let mapping = try container.decode([UUID: Int64].self, forKey: .mapping)
            self = .uploadResponse(mapping: mapping)
        case .downloadEntries:
            let fromIndex = try container.decode(Int64.self, forKey: .fromIndex)
            self = .downloadEntries(fromIndex: fromIndex)
        case .downloadResponse:
            let entries = try container.decode([DatabaseLogger.LogEntry].self, forKey: .entries)
            self = .downloadResponse(entries: entries)
        case .indexUpdate:
            let highestIndex = try container.decode(Int64.self, forKey: .highestIndex)
            self = .indexUpdate(highestIndex: highestIndex)
        case .error:
            let message = try container.decode(String.self, forKey: .message)
            self = .error(message: message)
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .handshake(let databaseId):
            try container.encode(MessageType.handshake, forKey: .type)
            try container.encode(databaseId, forKey: .databaseId)
        case .uploadEntries(let entries):
            try container.encode(MessageType.uploadEntries, forKey: .type)
            try container.encode(entries, forKey: .entries)
        case .uploadResponse(let mapping):
            try container.encode(MessageType.uploadResponse, forKey: .type)
            try container.encode(mapping, forKey: .mapping)
        case .downloadEntries(let fromIndex):
            try container.encode(MessageType.downloadEntries, forKey: .type)
            try container.encode(fromIndex, forKey: .fromIndex)
        case .downloadResponse(let entries):
            try container.encode(MessageType.downloadResponse, forKey: .type)
            try container.encode(entries, forKey: .entries)
        case .indexUpdate(let highestIndex):
            try container.encode(MessageType.indexUpdate, forKey: .type)
            try container.encode(highestIndex, forKey: .highestIndex)
        case .error(let message):
            try container.encode(MessageType.error, forKey: .type)
            try container.encode(message, forKey: .message)
        }
    }
}

// MARK: - Custom Errors

private enum WebSocketError: LocalizedError {
    case notConnected
    case invalidMessage
    case unexpectedResponse
    case serverError(String)
    
    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "WebSocket is not connected"
        case .invalidMessage:
            return "Received invalid message format"
        case .unexpectedResponse:
            return "Received unexpected response from server"
        case .serverError(let message):
            return "Server error: \(message)"
        }
    }
}

