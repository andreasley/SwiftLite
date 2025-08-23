import Foundation

public enum SQLiteStorageClass: String, Equatable, Sendable {
    case text
    case integer
    case real
    case blob
    case any

    init(for type: Any.Type)
    {
        self = switch type {
        case is any BinaryInteger.Type: .integer
        case is any BinaryFloatingPoint.Type: .real
        case is any StringProtocol.Type: .text
        case is Bool.Type: .integer
        case is Decimal.Type: .text
        default: .any
        }
    }
}
