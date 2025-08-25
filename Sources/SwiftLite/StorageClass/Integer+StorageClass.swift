extension Int: StorageClass.Integer {}
extension Int8: StorageClass.Integer {}
extension Int16: StorageClass.Integer {}
extension Int32: StorageClass.Integer {}
extension Int64: StorageClass.Integer {}

extension UInt: StorageClass.Integer {}
extension UInt8: StorageClass.Integer {}
extension UInt16: StorageClass.Integer {}
extension UInt32: StorageClass.Integer {}
extension UInt64: StorageClass.Integer {}


@available(macOS 15.0, *)
extension Int128: StorageClass.Blob
{
    public init(int: Int)
    {
        fatalError("Not implemented")
    }
}

@available(macOS 15.0, *)
extension UInt128: StorageClass.Blob
{
    public init(int: Int)
    {
        fatalError("Not implemented")
    }
}
