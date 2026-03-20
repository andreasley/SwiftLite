import Foundation
import SwiftLite

/// Message protocol for WebSocket communication (only for real-time updates)
enum WebSocketMessage: Codable {
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
