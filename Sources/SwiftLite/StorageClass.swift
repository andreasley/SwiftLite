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
        case is StorageConvertible.Integer.Type:
            self = .integer
        case is StorageConvertible.Text.Type:
            self = .text
        case is StorageConvertible.Blob.Type:
            self = .blob
        case is StorageConvertible.Real.Type:
            self = .real
        default:
            self = .any
        }
    }
}
