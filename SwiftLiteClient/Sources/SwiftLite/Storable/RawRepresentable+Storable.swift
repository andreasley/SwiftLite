public nonisolated extension RawRepresentable where RawValue: Storable
{
    var storageValue: RawValue { rawValue }
    
    init(storageValue: RawValue) throws
    {
        guard let value = Self.init(rawValue: storageValue) else {
            throw StorageConversionError.failedToConvert
        }
        self = value
    }
}
