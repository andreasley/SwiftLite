import Foundation

public enum StorageClass: String, Equatable, Sendable {

    enum ConversionError: Swift.Error {
        case invalidPrimaryKey
    }

    case text
    case integer
    case real
    case blob
    case any

    init(for type: Any.Type)
    {
        switch type {
        case is Integer:
            self = .integer
        case is Text:
            self = .text
        case is Blob:
            self = .blob
        case is Real:
            self = .real
        default:
            self = .any
        }
    }
}

extension StorageClass
{
    public protocol Integer
    {
        init(_ int: Int)
    }
    
    public protocol Text
    {
        init(cString: UnsafePointer<UInt8>) throws
    }
    
    public protocol Blob
    {
        // TODO
        init(int: Int)
    }
    
    public protocol Real
    {
        init(double: Double)
    }
    
    public protocol `Any`
    {
        // TODO
        init(int: Int)
    }
}
