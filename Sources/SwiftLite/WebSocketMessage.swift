import Foundation

public enum WebSocketMessage: Codable
{
    case handshake(databaseName: String)
    case indexUpdate(highestIndex: Int64)
    case error(message: String)
    
    enum CodingKeys: String, CodingKey {
        case type
        case databaseName
        case highestIndex
        case message
    }
    
    enum MessageType: String, Codable {
        case handshake
        case indexUpdate
        case error
    }
    
    public init(from decoder: Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(MessageType.self, forKey: .type)
        
        switch type {
        case .handshake:
            let databaseName = try container.decode(String.self, forKey: .databaseName)
            self = .handshake(databaseName: databaseName)
        case .indexUpdate:
            let highestIndex = try container.decode(Int64.self, forKey: .highestIndex)
            self = .indexUpdate(highestIndex: highestIndex)
        case .error:
            let message = try container.decode(String.self, forKey: .message)
            self = .error(message: message)
        }
    }
    
    public func encode(to encoder: Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .handshake(let databaseName):
            try container.encode(MessageType.handshake, forKey: .type)
            try container.encode(databaseName, forKey: .databaseName)
        case .indexUpdate(let highestIndex):
            try container.encode(MessageType.indexUpdate, forKey: .type)
            try container.encode(highestIndex, forKey: .highestIndex)
        case .error(let message):
            try container.encode(MessageType.error, forKey: .type)
            try container.encode(message, forKey: .message)
        }
    }
}
