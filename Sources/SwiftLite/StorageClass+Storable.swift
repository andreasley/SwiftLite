extension StorageClass: Storable
{
    init(for type: any SQLValueConvertible.Type)
    {
        self = type.storageClass
    }
}
