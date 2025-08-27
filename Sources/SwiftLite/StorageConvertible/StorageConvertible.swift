public protocol StorageConvertible2 {}

public enum StorageConvertible
{
    enum ConversionError: Swift.Error {
        case invalidPrimaryKey
        case failedToConvert
        case valueOutsideConvertibleRange
    }

    public protocol Integer
    {
        init(storageValue: Int64) throws
        var storageValue: Int64 { get }
    }

    public protocol Text
    {
        init(storageValue: String) throws
        var storageValue: String { get }
    }

    public protocol Blob
    {
        // TODO
        init(storageValue: OpaquePointer) throws
        var storageValue: OpaquePointer { get }
    }

    public protocol Real
    {
        init(storageValue: Double) throws
        var storageValue: Double { get }
    }

    public protocol `Any`
    {
        // TODO
        init(storageValue: Any) throws
        var storageValue: Any { get }
    }
}
