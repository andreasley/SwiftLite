nonisolated extension Float16: Storable
{
    public var storageValue: Double {
        Double(self)
    }
    
    public init(storageValue: Double)
    {
        self = Self(storageValue)
    }
}

nonisolated extension Float32: Storable
{
    public var storageValue: Double {
        Double(self)
    }

    public init(storageValue: Double)
    {
        self = Self(storageValue)
    }
}

nonisolated extension Float64: Storable
{
    public var storageValue: Double {
        self
    }

    public init(storageValue: Double)
    {
        self = storageValue
    }
}
