//nonisolated extension Float16: Storable
//{
//    public typealias StorageValue = Double
//    
//    public var storageValue: StorageValue {
//        Double(self)
//    }
//    
//    public init(storageValue: StorageValue)
//    {
//        self = Self(storageValue)
//    }
//}

nonisolated extension Float32: Storable
{
    public typealias StorageValue = Double

    public var storageValue: StorageValue {
        Double(self)
    }

    public init(storageValue: StorageValue)
    {
        self = Self(storageValue)
    }
}

nonisolated extension Float64: Storable
{
    public typealias StorageValue = Double

    public var storageValue: StorageValue {
        self
    }

    public init(storageValue: StorageValue)
    {
        self = storageValue
    }
}
