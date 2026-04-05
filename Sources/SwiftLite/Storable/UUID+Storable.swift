#if canImport(Foundation)
import Foundation

nonisolated extension UUID: Storable
{
    public typealias StorageValue = String
    
    public var storageValue: StorageValue {
        self.uuidString
    }
    
    public init(storageValue: StorageValue) throws
    {
        guard let uuid = UUID(uuidString: storageValue) else {
            throw StorageConversionError.failedToConvert
        }
        self = uuid
    }
}
#endif
