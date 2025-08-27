extension Float16: StorageConvertible.Real
{
    public var storageValue: Double {
        Double(self)
    }
    
    public init(storageValue: Double)
    {
        self = Self(storageValue)
    }
}

extension Float32: StorageConvertible.Real
{
    public var storageValue: Double {
        Double(self)
    }

    public init(storageValue: Double)
    {
        self = Self(storageValue)
    }
}

extension Float64: StorageConvertible.Real
{
    public var storageValue: Double {
        self
    }

    public init(storageValue: Double)
    {
        self = storageValue
    }
}
