import Foundation

extension FetchableObject
{   
    // TODO: This might need need special handling
    public init(cString: UnsafePointer<UInt8>) throws
    {
        let string = String(cString: cString)
        guard !string.isEmpty, let id = UUID(uuidString: string) else {
            throw StorageClass.ConversionError.invalidPrimaryKey
        }
        fatalError("Not implemented")
    }
}
