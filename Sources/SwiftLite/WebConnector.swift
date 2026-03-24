import Foundation

public actor WebConnector: SyncConnector
{
    // MARK: - Properties
    
    private var indexIncreaseCallback: IndexIncreaseHandler?
    private var didComeOnlineCallback: DidComeOnlineHandler?

    public private(set) var status: SyncConnectorStatus = .connecting {
        didSet {
            statusContinuation?.yield(status)
            if oldValue == .offline {
                didComeOnlineCallback?()
            }
        }
    }

    public nonisolated let databaseIdentifier: String
    
    public private(set) var errors: [SyncConnectorError] = []
    
    private var webSocketTask: URLSessionWebSocketTask?
    private let session: URLSession
    private var reconnectTask: Task<Void, Never>?

    public let syncUrl: URL
    public let uploadUrl: URL
    public let downloadUrl: URL
    public let indexUrl: URL

    private let encoder = JSONEncoder.forSwiftLiteSync
    private let decoder = JSONDecoder.forSwiftLiteSync

    // Status stream support
    private var statusContinuation: AsyncStream<SyncConnectorStatus>.Continuation?
    public nonisolated let statusStream: AsyncStream<SyncConnectorStatus>
    
    
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
        var continuation: AsyncStream<SyncConnectorStatus>.Continuation?
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

    // MARK: - SyncConnector Protocol

    public func onHighestRemoteIndexIncrease(_ callback: @escaping IndexIncreaseHandler)
    {
        indexIncreaseCallback = callback
    }

    public func onDidComeBackOnline(_ callback: @escaping DidComeOnlineHandler)
    {
        didComeOnlineCallback = callback
    }

    public func connect() async
    {
        status = .connecting
        
        // Create WebSocket task
        webSocketTask = session.webSocketTask(with: syncUrl)
        webSocketTask?.resume()
        
        // Send initial handshake
        do {
            let handshake = WebSocketMessage.handshake(databaseName: databaseIdentifier)
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
                addError(Error.invalidResponse)
                return nil
            }
            
            guard httpResponse.statusCode == 200 else {
                addError(Error.invalidResponse)
                return nil
            }
            
            let highestIndex = try decoder.decode(Int64.self, from: data)
            
            return highestIndex
        } catch {
            addError(error)
            return nil
        }
    }

    public func sendEntries(entries: [SyncClient.LogEntry]) async -> [UUID : Int64]
    {
        do {
            status = .transferring
            defer { status = .connected }
            
            var request = URLRequest(url: uploadUrl)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            request.httpBody = try encoder.encode(entries)

            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                addError(Error.invalidResponse)
                return [:]
            }
            
            guard httpResponse.statusCode == 200 else {
                addError(Error.serverError("HTTP \(httpResponse.statusCode)"))
                return [:]
            }
            
            let mapping = try decoder.decode([UUID: Int64].self, from: data)
            
            return mapping
        } catch {
            print("WebConnector: Server returned an error: \(error)")
            addError(error)
            return [:]
        }
    }
    
    public func getEntries(from index: Int64, limit: Int64 = 10_000) async -> [SyncClient.LogEntry]
    {
        do {
            status = .transferring
            defer { status = .connected }
            
            var request = URLRequest(url: downloadUrl.appending(queryItems: [.init(name: "from", value: String(index)), .init(name: "limit", value: String(limit))]))
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                addError(Error.invalidResponse)
                return []
            }
            
            guard httpResponse.statusCode == 200 else {
                addError(Error.serverError("HTTP \(httpResponse.statusCode)"))
                return []
            }
            
            let entries = try decoder.decode([SyncClient.LogEntry].self, from: data)
            
            defer { status = .connected }

            return entries
        } catch {
            print("WebConnector: Server returned an error: \(error)")
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
                addError(Error.serverError(errorMessage))
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
            throw Error.notConnected
        }
        
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
                throw Error.invalidMessage
            }
            data = textData
        @unknown default:
            throw Error.invalidMessage
        }
        
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
    
    private func addError(_ error: Swift.Error) {
        let syncError = SyncConnectorError(date: Date(), error: error)
        errors.append(syncError)
        
        // Keep only the last 100 errors
        if errors.count > 100 {
            errors.removeFirst(errors.count - 100)
        }
    }
}


// MARK: - Custom Errors

public nonisolated extension WebConnector
{
    enum Error: LocalizedError {
        case notConnected
        case invalidMessage
        case invalidResponse
        case unexpectedResponse
        case serverError(String)
        
        public var errorDescription: String? {
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
}
