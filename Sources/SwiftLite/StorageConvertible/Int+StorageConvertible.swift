extension Int: StorageConvertible.Integer
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

extension Int8: StorageConvertible.Integer
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

extension Int16: StorageConvertible.Integer
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

extension Int32: StorageConvertible.Integer
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

extension Int64: StorageConvertible.Integer
{
    public var storageValue: Int64 {
        self
    }
    
    public init(storageValue: Int64)
    {
        self = storageValue
    }
}

extension UInt: StorageConvertible.Integer
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

extension UInt8: StorageConvertible.Integer
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

extension UInt16: StorageConvertible.Integer
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

extension UInt32: StorageConvertible.Integer
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
extension UInt64: StorageConvertible.Integer
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


@available(macOS 15.0, *)
extension Int128: StorageConvertible.Blob
{
    // TODO
    public var storageValue: UnsafeRawPointer {
        fatalError("Not implemented")
    }
    
    public init(storageValue: UnsafeRawPointer)
    {
        fatalError("Not implemented")
    }
}

@available(macOS 15.0, *)
extension UInt128: StorageConvertible.Blob
{
    // TODO
    public var storageValue: UnsafeRawPointer {
        fatalError("Not implemented")
    }

    public init(storageValue: UnsafeRawPointer)
    {
        fatalError("Not implemented")
    }
}
