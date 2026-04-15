public extension RawRepresentable where RawValue: Storable
{
    typealias StorageValue = RawValue.StorageValue
    
    var storageValue: StorageValue { rawValue.storageValue }
    
    init(storageValue: StorageValue) throws
    {
        let rawValue = try RawValue(storageValue: storageValue)
        guard let value = Self.init(rawValue: rawValue) else {
            throw StorageConversionError.failedToConvert
        }
        self = value
    }
}
