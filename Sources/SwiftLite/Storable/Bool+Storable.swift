nonisolated extension Bool: Storable
{
    public typealias StorageValue = Int64

    public static var fallbackValue: Self? { false }

    public var storageValue: StorageValue {
        self ? 1 : 0
    }
    
    public init(storageValue: StorageValue) throws
    {
        if storageValue == 1 {
            self = true
        } else if storageValue == 0 {
            self = false
        } else {
            throw StorageConversionError.valueOutsideConvertibleRange
        }
    }
}
