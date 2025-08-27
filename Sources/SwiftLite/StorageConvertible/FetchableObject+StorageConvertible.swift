import Foundation

extension FetchableObject
{
    public var storageValue: String {
        self.id.uuidString
    }
    
    // TODO: This might need need special handling
    public init(storageValue: String) throws
    {
        guard !storageValue.isEmpty, let id = UUID(uuidString: storageValue) else {
            throw StorageConvertible.ConversionError.invalidPrimaryKey
        }
        print(id)
        fatalError("Not implemented")
    }
}
