nonisolated extension String: Storable
{
    public typealias StorageValue = String
    public static var fallbackValue: String? { "" }

    public var storageValue: StorageValue {
        self
    }
    
    public init(storageValue: StorageValue) throws
    {
        self = storageValue
    }
}
