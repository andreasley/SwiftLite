import Foundation

public nonisolated enum StorageClass: String, Equatable, Sendable {
    case text
    case integer
    case real
    case blob
    case any
    case undefined = ""

    public init?(rawValue: String) {
        self = switch rawValue.lowercased() {
        case "text": .text
        case "integer": .integer
        case "real": .real
        case "blob": .blob
        case "any": .any
        default: .undefined
        }
    }    
}
