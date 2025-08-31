extension Bool: StorageConvertible.Integer
{
    public var storageValue: Int64 {
        self ? 1 : 0
    }
    
    public init(storageValue: Int64) throws
    {
        if storageValue == 1 {
            self = true
        } else if storageValue == 0 {
            self = false
        } else {
            throw StorageConvertible.ConversionError.valueOutsideConvertibleRange
        }
    }
}
