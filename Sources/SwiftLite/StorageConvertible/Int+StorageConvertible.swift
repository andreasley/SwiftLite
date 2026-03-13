nonisolated extension Int: StorageConvertible.Integer
{
    public var storageValue: Int64 {
        Int64(self)
    }
    
    public init(storageValue: Int64) throws
    {
        guard let value = Self(exactly: storageValue) else {
            throw StorageConvertible.ConversionError.valueOutsideConvertibleRange
        }
        self = value
    }
}

nonisolated extension Int8: StorageConvertible.Integer
{
    public var storageValue: Int64 {
        Int64(self)
    }
    
    public init(storageValue: Int64) throws
    {
        guard let value = Self(exactly: storageValue) else {
            throw StorageConvertible.ConversionError.valueOutsideConvertibleRange
        }
        self = value
    }
}

nonisolated extension Int16: StorageConvertible.Integer
{
    public var storageValue: Int64 {
        Int64(self)
    }
    
    public init(storageValue: Int64) throws
    {
        guard let value = Self(exactly: storageValue) else {
            throw StorageConvertible.ConversionError.valueOutsideConvertibleRange
        }
        self = value
    }
}

nonisolated extension Int32: StorageConvertible.Integer
{
    public var storageValue: Int64 {
        Int64(self)
    }
    
    public init(storageValue: Int64) throws
    {
        guard let value = Self(exactly: storageValue) else {
            throw StorageConvertible.ConversionError.valueOutsideConvertibleRange
        }
        self = value
    }
}

nonisolated extension Int64: StorageConvertible.Integer
{
    public var storageValue: Int64 {
        self
    }
    
    public init(storageValue: Int64)
    {
        self = storageValue
    }
}

nonisolated extension UInt: StorageConvertible.Integer
{
    public var storageValue: Int64 {
        Int64(self)
    }
    
    public init(storageValue: Int64) throws
    {
        guard let value = Self(exactly: storageValue) else {
            throw StorageConvertible.ConversionError.valueOutsideConvertibleRange
        }
        self = value
    }
}

nonisolated extension UInt8: StorageConvertible.Integer
{
    public var storageValue: Int64 {
        Int64(self)
    }
    
    public init(storageValue: Int64) throws
    {
        guard let value = Self(exactly: storageValue) else {
            throw StorageConvertible.ConversionError.valueOutsideConvertibleRange
        }
        self = value
    }
}

nonisolated extension UInt16: StorageConvertible.Integer
{
    public var storageValue: Int64 {
        Int64(self)
    }
    
    public init(storageValue: Int64) throws
    {
        guard let value = Self(exactly: storageValue) else {
            throw StorageConvertible.ConversionError.valueOutsideConvertibleRange
        }
        self = value
    }
}

nonisolated extension UInt32: StorageConvertible.Integer
{
    public var storageValue: Int64 {
        Int64(self)
    }
    
    public init(storageValue: Int64) throws
    {
        guard let value = Self(exactly: storageValue) else {
            throw StorageConvertible.ConversionError.valueOutsideConvertibleRange
        }
        self = value
    }
}

// Store UInt64 by flipping the top bit (thereby shifting the value into the range of an Int64). This way it's possible to store the value in the (same-sized) `INTEGER` column and keep the ability to INDEX and ORDER.
nonisolated extension UInt64: StorageConvertible.Integer
{
    public var storageValue: Int64 {
        // Flip the top bit to map from UInt64 to Int64
        Int64(bitPattern: self ^ 0x8000_0000_0000_0000)
    }
    
    public init(storageValue: Int64)
    {
        // Flip the top bit to map from Int64 to UInt64
        self = UInt64(bitPattern: storageValue) ^ 0x8000_0000_0000_0000
    }
}


// TODO: Implement?
//@available(macOS 15.0, *)
//nonisolated extension Int128: StorageConvertible.Blob
//{
//    public var storageValue: UnsafeRawPointer {
//        fatalError("Not implemented")
//    }
//    
//    public init(storageValue: UnsafeRawPointer)
//    {
//        fatalError("Not implemented")
//    }
//}
//
//@available(macOS 15.0, *)
//nonisolated extension UInt128: StorageConvertible.Blob
//{
//    public var storageValue: UnsafeRawPointer {
//        fatalError("Not implemented")
//    }
//
//    public init(storageValue: UnsafeRawPointer)
//    {
//        fatalError("Not implemented")
//    }
//}
