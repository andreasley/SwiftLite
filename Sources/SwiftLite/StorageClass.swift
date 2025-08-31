import Foundation

public enum StorageClass: String, Equatable, Sendable, StorageConvertible.Text {
    public var storageValue: String { rawValue }
    
    case text
    case integer
    case real
    case blob
    case any
    case undefined = ""

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
    
    public init(storageValue: String) throws
    {
        self = .init(rawValue: storageValue) ?? .undefined
    }
}
