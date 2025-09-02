public struct CompositeIndex<T> : AnyIndex, @unchecked Sendable // TODO: Make properly sendable
{
    let name: String?
    let columns: [String: PartialKeyPath<T>]
    
    public init(name: String? = nil, columns: [String: PartialKeyPath<T>])
    {
        self.name = name
        self.columns = columns
    }
}
