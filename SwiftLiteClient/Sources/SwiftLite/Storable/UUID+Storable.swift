#if canImport(Foundation)
import Foundation

nonisolated extension UUID: Storable
{
    public var storageValue: String {
        self.uuidString
    }
    
    public init(storageValue: String) throws
    {
        guard let uuid = UUID(uuidString: storageValue) else {
            throw StorageConversionError.failedToConvert
        }
        self = uuid
    }
}
#endif
