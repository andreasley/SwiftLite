import Foundation
#if canImport(Network)
import Network
#endif

public actor WebSyncConnector: SyncConnector
{
    private var indexIncreaseCallback: IndexIncreaseHandler?
    private var didComeOnlineCallback: DidComeOnlineHandler?

    public private(set) var status: SyncConnectorStatus = .connecting {
        didSet {
            statusContinuation?.yield(status)
            if (oldValue == .offline || oldValue == .connecting) && status == .connected {
                didComeOnlineCallback?()
            }
        }
    }

    public nonisolated let databaseName: String
    public private(set) var databaseId: UUID?

    public private(set) var errors: [SyncConnectorError] = []
    
    private var webSocketTask: URLSessionWebSocketTask?
    private let session: URLSession
    private var reconnectTask: Task<Void, Never>?

    public let server: String
    public let databaseIdUrl: URL

    public var syncUrl: URL?
    public var uploadUrl: URL?
    public var downloadUrl: URL?
    public var indexUrl: URL?

    private let encoder = JSONEncoder.forSwiftLiteSync
    private let decoder = JSONDecoder.forSwiftLiteSync
    
    #if canImport(Network)
    private let monitor = NWPathMonitor()
    #endif

    // Status stream support
    private var statusContinuation: AsyncStream<SyncConnectorStatus>.Continuation?
    public nonisolated let statusStream: AsyncStream<SyncConnectorStatus>
    
    
    public init(server: String, databaseName: String, session: URLSession = .shared)
    {
        self.server = server
        self.databaseIdUrl = URL(string: "http://\(server)/\(databaseName)/id")!

        self.databaseName = databaseName
        self.session = session
        
        // Create the status stream
        var continuation: AsyncStream<SyncConnectorStatus>.Continuation?
        self.statusStream = AsyncStream { cont in
            continuation = cont
            // Yield the initial status
            cont.yield(.connecting)
        }
        self.statusContinuation = continuation
        
        #if canImport(Network)
        monitor.pathUpdateHandler = { [weak self] path in
            Task {
                await self?.setIsOffline(path.status != .satisfied)
            }
        }
        monitor.start(queue: .global())
        #endif
    }
    
    deinit
    {
        reconnectTask?.cancel()
        statusContinuation?.finish()
        
        #if canImport(Network)
        monitor.cancel()
        #endif
    }
    
    func setIsOffline(_ isOffline: Bool) async
    {
        if isOffline {
            status = .offline
        } else {
            guard let databaseId else { return }
            try? await connect(databaseId: databaseId)
        }
    }

    public func onHighestRemoteIndexIncrease(_ callback: @escaping IndexIncreaseHandler)
    {
        indexIncreaseCallback = callback
    }

    public func onDidComeBackOnline(_ callback: @escaping DidComeOnlineHandler)
    {
        didComeOnlineCallback = callback
    }

    public func connect(databaseId: UUID) async throws
    {
        status = .connecting

        self.databaseId = databaseId
        
        let basePath = "\(server)/\(databaseName)/\(databaseId)"
        self.syncUrl = URL(string: "ws://\(basePath)/sync")!
        self.uploadUrl = URL(string: "http://\(basePath)/upload")!
        self.downloadUrl = URL(string: "http://\(basePath)/download")!
        self.indexUrl = URL(string: "http://\(basePath)/highestIndex")!

        guard let syncUrl else { throw Error.urlNotConfigured }
        
        webSocketTask = session.webSocketTask(with: syncUrl)
        webSocketTask?.resume()


        do {
            let handshake = WebSocketSyncMessage.handshake(databaseName: databaseName, databaseId: databaseId)
            try await send(message: handshake)
            status = .connected
            
            Task {
                await startListeningForIndexIncreaseNotifications()
            }
        } catch {
            addError(error)
            await scheduleReconnect()
        }
    }
    
    public func getDatabaseId() async throws -> UUID?
    {
        var request = URLRequest(url: databaseIdUrl)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw Error.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw Error.serverError("HTTP \(httpResponse.statusCode)")
        }
        
        let databaseId = try decoder.decode(UUID.self, from: data)
        
        return databaseId
    }
    
    public func getHighestRemoteIndex() async -> Int64?
    {
        do {
            guard let indexUrl else { throw Error.urlNotConfigured }
            
            var request = URLRequest(url: indexUrl)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw Error.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                throw Error.serverError("HTTP \(httpResponse.statusCode)")
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
            guard let uploadUrl else { throw Error.urlNotConfigured }

            status = .transferring
            defer { status = .connected }
            
            var request = URLRequest(url: uploadUrl)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            request.httpBody = try encoder.encode(entries)

            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw Error.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                throw Error.serverError("HTTP \(httpResponse.statusCode)")
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
            guard let downloadUrl else { throw Error.urlNotConfigured }

            status = .transferring
            defer { status = .connected }
            
            var request = URLRequest(url: downloadUrl.appending(queryItems: [.init(name: "from", value: String(index)), .init(name: "limit", value: String(limit))]))
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw Error.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                throw Error.serverError("HTTP \(httpResponse.statusCode)")
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
    
    
    private func startListeningForIndexIncreaseNotifications() async
    {
        guard let webSocketTask = webSocketTask else { return }
        
        while status == .connected {
            do {
                let message = try await webSocketTask.receive()
                await handleIncomingMessage(message)
            } catch {
                addError(error)
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
    
    private func send(message: WebSocketSyncMessage) async throws
    {
        guard let webSocketTask = webSocketTask else {
            throw Error.notConnected
        }
        
        let data = try encoder.encode(message)
        
        let urlMessage = URLSessionWebSocketTask.Message.data(data)
        try await webSocketTask.send(urlMessage)
    }
    
    private func parseMessage(_ message: URLSessionWebSocketTask.Message) throws -> WebSocketSyncMessage
    {
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
        
        return try decoder.decode(WebSocketSyncMessage.self, from: data)
    }
    
    private func scheduleReconnect() async
    {
        reconnectTask?.cancel()
        
        guard let databaseId else { return }
        reconnectTask = Task {
            try? await Task.sleep(for: .seconds(5))
            
            if !Task.isCancelled {
                try? await connect(databaseId: databaseId)
            }
        }
    }
    
    private func addError(_ error: Swift.Error)
    {
        status = .error
        
        Task {
            await scheduleReconnect()
        }

        let syncError = SyncConnectorError(date: Date(), error: error)
        errors.append(syncError)
        print("Web connector error:", error)
        
        // Keep only the last 100 errors
        if errors.count > 100 {
            errors.removeFirst(errors.count - 100)
        }
    }
}


public nonisolated extension WebSyncConnector
{
    enum Error: LocalizedError {
        case notConnected
        case invalidMessage
        case invalidResponse
        case unexpectedResponse
        case serverError(String)
        case failedToFindDatabaseId
        case urlNotConfigured

        public var errorDescription: String? {
            return switch self {
            case .notConnected:
                "WebSocket is not connected"
            case .invalidMessage:
                "Received invalid message format"
            case .invalidResponse:
                "Received invalid HTTP response"
            case .unexpectedResponse:
                "Received unexpected response from server"
            case .serverError(let message):
                "Server error: \(message)"
            case .failedToFindDatabaseId:
                "Failed to find database ID"
            case .urlNotConfigured:
                "URL not configured; Database ID not found?"
            }
        }
    }
}
