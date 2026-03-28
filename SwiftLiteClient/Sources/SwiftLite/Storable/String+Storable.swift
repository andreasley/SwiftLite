nonisolated extension String: Storable
{
    public typealias StorageValue = String
    
    public var storageValue: StorageValue {
        self
    }
    
    public init(storageValue: StorageValue) throws
    {
        self = storageValue
    }
}
