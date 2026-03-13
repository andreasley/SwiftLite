import Foundation

public nonisolated enum StorageConvertible
{
    public enum ConversionError: Swift.Error {
        case invalidPrimaryKey
        case failedToConvert
        case unexpectedNull
        case valueOutsideConvertibleRange
    }
    
    public nonisolated protocol Integer: SQLValueConvertible
    {
        init(storageValue: Int64) throws
        var storageValue: Int64 { get }
    }
    
    public nonisolated protocol Text: SQLValueConvertible
    {
        init(storageValue: String) throws
        var storageValue: String { get }
    }
    
    public nonisolated protocol Blob: SQLValueConvertible
    {
        init(storageValue: Data) throws
        var storageValue: Data { get }
    }
    
    public nonisolated protocol Real: SQLValueConvertible
    {
        init(storageValue: Double) throws
        var storageValue: Double { get }
    }
}
