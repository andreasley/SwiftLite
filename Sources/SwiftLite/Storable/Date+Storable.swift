#if canImport(Foundation)
import Foundation

nonisolated extension Date: Storable
{
    public typealias StorageValue = Double
    
    public var storageValue: StorageValue {
        timeIntervalSince1970
    }
    
    public init(storageValue: StorageValue)
    {
        self.init(timeIntervalSince1970: storageValue)
    }
}
#endif
