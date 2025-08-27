import Foundation

public enum StorageClass: String, Equatable, Sendable {
    case text
    case integer
    case real
    case blob
    case any

    init(for type: Any.Type)
    {
        switch type {
        case is StorageConvertible.Integer:
            self = .integer
        case is StorageConvertible.Text:
            self = .text
        case is StorageConvertible.Blob:
            self = .blob
        case is StorageConvertible.Real:
            self = .real
        default:
            self = .any
        }
    }
}
