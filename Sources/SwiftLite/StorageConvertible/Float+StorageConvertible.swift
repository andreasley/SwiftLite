nonisolated extension Float16: StorageConvertible.Real
{
    public var storageValue: Double {
        Double(self)
    }
    
    public init(storageValue: Double)
    {
        self = Self(storageValue)
    }
}

nonisolated extension Float32: StorageConvertible.Real
{
    public var storageValue: Double {
        Double(self)
    }

    public init(storageValue: Double)
    {
        self = Self(storageValue)
    }
}

nonisolated extension Float64: StorageConvertible.Real
{
    public var storageValue: Double {
        self
    }

    public init(storageValue: Double)
    {
        self = storageValue
    }
}
