import Foundation

public actor WebSocketSyncTransport: SyncTransport
{
    // MARK: - Properties
    
    private var indexIncreaseCallback: IndexIncreaseHandler? // this needs to be called when the server informs this client that there are new entries available

    public private(set) var status: SyncTransportStatus = .connecting {
        didSet {
            statusContinuation?.yield(status)
        }
    }

    public nonisolated let databaseIdentifier: String
    
    public private(set) var syncErrors: [SyncError] = []
    
    private var webSocketTask: URLSessionWebSocketTask?
    private let session: URLSession
    private var reconnectTask: Task<Void, Never>?

    public let syncUrl: URL
    public let uploadUrl: URL
    public let downloadUrl: URL
    public let indexUrl: URL

    // Status stream support
    private var statusContinuation: AsyncStream<SyncTransportStatus>.Continuation?
    public nonisolated let statusStream: AsyncStream<SyncTransportStatus>
    
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
    
    public init(server: String, databaseIdentifier: String = "test", session: URLSession = .shared)
    {
        self.syncUrl = URL(string: "ws://\(server)/\(databaseIdentifier)/sync")!
        self.uploadUrl = URL(string: "http://\(server)/\(databaseIdentifier)/upload")!
        self.downloadUrl = URL(string: "http://\(server)/\(databaseIdentifier)/download")!
        self.indexUrl = URL(string: "http://\(server)/\(databaseIdentifier)/highestIndex")!

        self.databaseIdentifier = databaseIdentifier
        self.session = session
        
        // Create the status stream
        var continuation: AsyncStream<SyncTransportStatus>.Continuation?
        self.statusStream = AsyncStream { cont in
            continuation = cont
            // Yield the initial status
            cont.yield(.connecting)
        }
        self.statusContinuation = continuation
    }
    
    deinit
    {
        reconnectTask?.cancel()
        statusContinuation?.finish()
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
        webSocketTask = session.webSocketTask(with: syncUrl)
        webSocketTask?.resume()
        
        // Send initial handshake
        do {
            let handshake = WebSocketMessage.handshake(databaseId: databaseIdentifier)
            try await send(message: handshake)
            status = .connected
            
            // Start listening for incoming messages (index updates)
            Task {
                await startListening()
            }
        } catch {
            status = .offline
            addError(error)
            await scheduleReconnect()
        }
    }

    public func getHighestRemoteIndex() async -> Int64?
    {
        do {
            var request = URLRequest(url: indexUrl)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                addError(WebSocketError.invalidResponse)
                return nil
            }
            
            guard httpResponse.statusCode == 200 else {
                addError(WebSocketError.invalidResponse)
                return nil
            }
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let highestIndex = try decoder.decode(Int64.self, from: data)
            
            return highestIndex
        } catch {
            addError(error)
            return nil
        }
    }

    public func sendEntries(entries: [DatabaseLogger.LogEntry]) async -> [UUID : Int64]
    {
        do {
            status = .syncing(Progress(totalUnitCount: Int64(entries.count)))
            defer { status = .connected }
            
            var request = URLRequest(url: uploadUrl)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            request.httpBody = try encoder.encode(entries)
            
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                addError(WebSocketError.invalidResponse)
                return [:]
            }
            
            guard httpResponse.statusCode == 200 else {
                addError(WebSocketError.serverError("HTTP \(httpResponse.statusCode)"))
                return [:]
            }
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let mapping = try decoder.decode([UUID: Int64].self, from: data)
            
            return mapping
        } catch {
            addError(error)
            return [:]
        }
    }
    
    public func getEntries(from index: Int64, limit: Int64 = 10_000) async -> [DatabaseLogger.LogEntry]
    {
        do {
            status = .syncing(Progress(totalUnitCount: 1))
            defer { status = .connected }
            
            var request = URLRequest(url: downloadUrl.appending(queryItems: [.init(name: "from", value: String(index)), .init(name: "limit", value: String(limit))]))
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                addError(WebSocketError.invalidResponse)
                return []
            }
            
            guard httpResponse.statusCode == 200 else {
                addError(WebSocketError.serverError("HTTP \(httpResponse.statusCode)"))
                return []
            }
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let entries = try decoder.decode([DatabaseLogger.LogEntry].self, from: data)
            
            status = .syncing(Progress(totalUnitCount: Int64(entries.count)))
            defer { status = .connected }

            return entries
        } catch {
            addError(error)
            return []
        }
    }
    
    
    // MARK: - Private Methods
    
    private func startListening() async {
        guard let webSocketTask = webSocketTask else { return }
        
        while status == .connected {
            do {
                let message = try await webSocketTask.receive()
                await handleIncomingMessage(message)
            } catch {
                if status == .connected {
                    status = .offline
                    addError(error)
                    await scheduleReconnect()
                }
                break
            }
        }
    }
    
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
    case indexUpdate(highestIndex: Int64)
    case error(message: String)
    
    enum CodingKeys: String, CodingKey {
        case type
        case databaseId
        case highestIndex
        case message
    }
    
    enum MessageType: String, Codable {
        case handshake
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
    case invalidResponse
    case unexpectedResponse
    case serverError(String)
    
    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "WebSocket is not connected"
        case .invalidMessage:
            return "Received invalid message format"
        case .invalidResponse:
            return "Received invalid HTTP response"
        case .unexpectedResponse:
            return "Received unexpected response from server"
        case .serverError(let message):
            return "Server error: \(message)"
        }
    }
}

