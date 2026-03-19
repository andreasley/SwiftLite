import Foundation
import SwiftLite

/// Message protocol matching the client's WebSocketMessage format
enum WebSocketMessage: Codable {
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
