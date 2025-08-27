extension String: StorageConvertible.Text {
    public var storageValue: String {
        self
    }
    
    public init(storageValue: String) throws
    {
        self = storageValue
    }
}
