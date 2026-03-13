#if canImport(Foundation)
import Foundation

nonisolated extension UUID: StorageConvertible.Text
{
    public var storageValue: String {
        self.uuidString
    }
    
    public init(storageValue: String) throws
    {
        guard let uuid = UUID(uuidString: storageValue) else {
            throw StorageConvertible.ConversionError.failedToConvert
        }
        self = uuid
    }
}
#endif
