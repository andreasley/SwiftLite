import Foundation

public nonisolated enum SQLValue: Equatable, Hashable, Sendable, Codable {
    case string(String)
    case int(Int64)
    case double(Double)
    case data(Data)
    case null
}

nonisolated extension SQLValue: CustomDebugStringConvertible
{
    public var debugDescription: String {
        return switch self {
        case .string(let string): string
        case .int(let int): String(int)
        case .double(let double): String(double)
        case .data(let d): "\(d.count) bytes of data"
        case .null: "NULL"
        }
    }
}

