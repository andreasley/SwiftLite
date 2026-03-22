import Foundation
import Foundation
import SwiftLite
import SQLite3
import HummingbirdWebSocket
import Hummingbird

// Helper function for SQLite transient destructor
nonisolated let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Manages the server-side database that stores operation logs from multiple clients
actor ServerDatabaseManager {
    private var databases: [String: ServerDatabase] = [:]
    private var clientConnections: [UUID: ClientConnection] = [:]
    
    init() async throws {
        // Ensure data directory exists
        let dataDir = URL.applicationSupportDirectory
            .appendingPathComponent("SwiftLiteWebSocketSyncServer", isDirectory: true)
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
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
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
                        clientConnections.removeValue(forKey: sessionId)
                        print("Failed to send index update to session \(sessionId): \(error)")
                        print("Removing session \(sessionId) from client connection list")
                    }
                }
            }
        }
    }
    
    func storeEntries(entries: [DatabaseLogger.LogEntry], databaseId: String) async throws -> [UUID: Int64] {
        let database = try await getOrCreateDatabase(databaseId: databaseId)
        return try await database.storeEntries(entries: entries)
    }
    
    func getEntries(fromIndex: Int64, databaseId: String, limit: Int64) async throws -> [DatabaseLogger.LogEntry] {
        let database = try await getOrCreateDatabase(databaseId: databaseId)
        return try await database.getEntries(fromIndex: fromIndex, limit: limit)
    }
    
    private func getOrCreateDatabase(databaseId: String) async throws -> ServerDatabase {
        if let existing = databases[databaseId] {
            return existing
        }
        
        let newDatabase = try await ServerDatabase(databaseId: databaseId)
        databases[databaseId] = newDatabase
        return newDatabase
    }
}

/// Represents a single database on the server (one per client database ID)
actor ServerDatabase {
    private let databaseId: String
    private let databaseURL: URL
    private let connectionHandle: OpaquePointer
    public private(set) var highestIndex: Int64 = 0
    
    init(databaseId: String) async throws {
        self.databaseId = databaseId
        
        // Create database file path
        let dataDir = URL.applicationSupportDirectory
            .appendingPathComponent("SwiftLiteWebSocketSyncServer", isDirectory: true)
        self.databaseURL = dataDir.appendingPathComponent("\(databaseId).sqlite", isDirectory: false)
        
        // Open database
        var handle: OpaquePointer?
        let status = SQLiteStatus(sqlite3_open(databaseURL.path, &handle))
        guard status == .ok, let handle else {
            throw ServerError.databaseError("Failed to open database: \(status.description)")
        }
        self.connectionHandle = handle
        
        // Initialize schema
        try initializeSchema()
        
        // Load highest index
        self.highestIndex = try fetchHighestIndex()
        
        print("📂 Database \(databaseId) opened at: \(self.databaseURL.path(percentEncoded: false))")
        print("Highest index: \(highestIndex)")
    }
    
    isolated deinit
    {
        sqlite3_close(connectionHandle)
    }
    
    func storeEntries(entries: [DatabaseLogger.LogEntry]) throws -> [UUID: Int64] {
        var mapping: [UUID: Int64] = [:]
        
        // Begin transaction
        try execute(sql: "BEGIN TRANSACTION")
        
        defer {
            // Commit transaction (or rollback if there's an error)
            try? execute(sql: "COMMIT")
        }
        
        let insertSQL = """
        INSERT INTO operation_log (
            id, timestamp, transaction_id, operation_type, 
            table_name, object_id, column_name, new_value,
            metadata, user, synchronized_index
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        
        for entry in entries {
            highestIndex += 1
            
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(connectionHandle, insertSQL, -1, &stmt, nil) == SQLITE_OK else {
                throw ServerError.databaseError("Failed to prepare insert statement")
            }
            defer { sqlite3_finalize(stmt) }
            
            // Bind parameters
            sqlite3_bind_text(stmt, 1, entry.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 2, entry.timestamp.timeIntervalSince1970)
            sqlite3_bind_text(stmt, 3, entry.transactionId.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 4, entry.operationType.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 5, entry.tableName, -1, SQLITE_TRANSIENT)
            
            if let objectId = entry.objectId {
                sqlite3_bind_text(stmt, 6, objectId.uuidString, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 6)
            }
            
            if let columnName = entry.columnName {
                sqlite3_bind_text(stmt, 7, columnName, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 7)
            }
            
            if let newValue = entry.newValue {
                try bindSQLValue(newValue, to: stmt, at: 8)
            } else {
                sqlite3_bind_null(stmt, 8)
            }
            
            if let metadata = entry.metadata {
                sqlite3_bind_text(stmt, 9, metadata, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 9)
            }
            
            if let user = entry.user {
                sqlite3_bind_text(stmt, 10, user, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 10)
            }
            
            sqlite3_bind_int64(stmt, 11, highestIndex)
            sqlite3_bind_int(stmt, 12, 0)
            
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw ServerError.databaseError("Failed to insert entry")
            }
            
            mapping[entry.id] = highestIndex
        }
        
        return mapping
    }
    
    func getEntries(fromIndex: Int64, limit: Int64) throws -> [DatabaseLogger.LogEntry] {
        let querySQL = """
        SELECT id, timestamp, transaction_id, operation_type,
               table_name, object_id, column_name, new_value,
               metadata, user, synchronized_index
        FROM operation_log
        WHERE transaction_id IN (
            SELECT DISTINCT transaction_id
            FROM (
                SELECT transaction_id
                FROM operation_log
                WHERE synchronized_index > ?
                ORDER BY synchronized_index ASC
                LIMIT ?
            )
        )
        ORDER BY synchronized_index ASC
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(connectionHandle, querySQL, -1, &stmt, nil) == SQLITE_OK else {
            throw ServerError.databaseError("Failed to prepare query")
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_int64(stmt, 1, fromIndex)
        sqlite3_bind_int64(stmt, 2, limit)

        var entries: [DatabaseLogger.LogEntry] = []
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            let entry = try parseLogEntry(from: stmt)
            entries.append(entry)
        }
        
        return entries
    }
    
    // MARK: - Private Helpers
    
    private func initializeSchema() throws {
        let createTableSQL = """
        CREATE TABLE IF NOT EXISTS operation_log (
            id TEXT PRIMARY KEY NOT NULL,
            timestamp REAL NOT NULL,
            transaction_id TEXT NOT NULL,
            operation_type TEXT NOT NULL,
            table_name TEXT NOT NULL,
            object_id TEXT,
            column_name TEXT,
            new_value ANY,
            metadata TEXT,
            user TEXT,
            synchronized_index INTEGER
        ) STRICT;
        """
        
        let createIndexSQL = [
            "CREATE INDEX IF NOT EXISTS idx_timestamp ON operation_log(timestamp);",
            "CREATE INDEX IF NOT EXISTS idx_transaction_id ON operation_log(transaction_id);",
            "CREATE INDEX IF NOT EXISTS idx_operation_type ON operation_log(operation_type);",
            "CREATE INDEX IF NOT EXISTS idx_table_name ON operation_log(table_name);",
            "CREATE INDEX IF NOT EXISTS idx_object_id ON operation_log(object_id);",
            "CREATE INDEX IF NOT EXISTS idx_synchronized_index ON operation_log(synchronized_index);",
        ]
        
        try execute(sql: createTableSQL)

        for indexSQL in createIndexSQL {
            try execute(sql: indexSQL)
        }
    }
    
    private func fetchHighestIndex() throws -> Int64 {
        let querySQL = "SELECT MAX(synchronized_index) FROM operation_log"
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(connectionHandle, querySQL, -1, &stmt, nil) == SQLITE_OK else {
            throw ServerError.databaseError("Failed to prepare query")
        }
        defer { sqlite3_finalize(stmt) }
        
        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return 0
        }
        
        let value = sqlite3_column_int64(stmt, 0)
        return value
    }
    
    private func execute(sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        let status = SQLiteStatus(sqlite3_exec(connectionHandle, sql, nil, nil, &error))
        
        if status != .ok {
            let errorMessage = error.map { String(cString: $0) } ?? "Unknown error"
            sqlite3_free(error)
            throw ServerError.databaseError("SQL execution failed: \(errorMessage)")
        }
    }
    
    private func bindSQLValue(_ value: SQLValue, to stmt: OpaquePointer?, at index: Int32) throws {
        switch value {
        case .int(let int):
            sqlite3_bind_int64(stmt, index, int)
        case .double(let double):
            sqlite3_bind_double(stmt, index, double)
        case .string(let string):
            sqlite3_bind_text(stmt, index, string, -1, SQLITE_TRANSIENT)
        case .data(let data):
            data.withUnsafeBytes { bytes in
                _ = sqlite3_bind_blob(stmt, index, bytes.baseAddress, Int32(data.count), SQLITE_TRANSIENT)
            }
        case .null:
            sqlite3_bind_null(stmt, index)
        }
    }
    
    private func parseLogEntry(from stmt: OpaquePointer?) throws -> DatabaseLogger.LogEntry
    {
        guard let idString = sqlite3_column_text(stmt, 0).map({ String(cString: $0) }),
              let id = UUID(uuidString: idString) else {
            throw ServerError.databaseError("Invalid entry ID")
        }
        
        let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1))
        
        guard let transactionIdString = sqlite3_column_text(stmt, 2).map({ String(cString: $0) }),
              let transactionId = UUID(uuidString: transactionIdString) else {
            throw ServerError.databaseError("Invalid transaction ID")
        }
        
        guard let operationTypeString = sqlite3_column_text(stmt, 3).map({ String(cString: $0) }),
              let operationType = DatabaseLogger.OperationType(rawValue: operationTypeString) else {
            throw ServerError.databaseError("Invalid operation type")
        }

        guard let tableName = sqlite3_column_text(stmt, 4).map({ String(cString: $0) }) else {
            throw ServerError.databaseError("Invalid table name")
        }

        let objectId = sqlite3_column_text(stmt, 5).flatMap { UUID(uuidString: String(cString: $0)) }
        let columnName = sqlite3_column_text(stmt, 6).map { String(cString: $0) }
        
        let newValue: SQLValue?
        let columnType = sqlite3_column_type(stmt, 7)
        switch columnType {
        case SQLITE_INTEGER:
            newValue = .int(sqlite3_column_int64(stmt, 7))
        case SQLITE_FLOAT:
            newValue = .double(sqlite3_column_double(stmt, 7))
        case SQLITE_TEXT:
            newValue = sqlite3_column_text(stmt, 7).map { .string(String(cString: $0)) }
        case SQLITE_BLOB:
            if let bytes = sqlite3_column_blob(stmt, 7) {
                let count = Int(sqlite3_column_bytes(stmt, 7))
                newValue = .data(Data(bytes: bytes, count: count))
            } else {
                newValue = nil
            }
        default:
            newValue = nil
        }
        
        let metadata = sqlite3_column_text(stmt, 8).map { String(cString: $0) }
        let user = sqlite3_column_text(stmt, 9).map { String(cString: $0) }
        
        let synchronizedIndex: Int64?
        if sqlite3_column_type(stmt, 10) != SQLITE_NULL {
            synchronizedIndex = sqlite3_column_int64(stmt, 10)
        } else {
            synchronizedIndex = nil
        }
                
        return DatabaseLogger.LogEntry(
            id: id,
            timestamp: timestamp,
            transactionId: transactionId,
            operationType: operationType,
            tableName: tableName,
            objectId: objectId,
            columnName: columnName,
            newValue: newValue,
            metadata: metadata,
            user: user,
            synchronizedIndex: synchronizedIndex
        )
    }
}

// MARK: - Supporting Types

struct ClientConnection: Sendable {
    let session: ClientSession
    let outbound: WebSocketOutboundWriter
}

