public class Changeset
{
    private(set) var changes = [ChangedObject]()
    var needsSaving: Bool { !changes.isEmpty }
    let isolation: (any Actor)?
    
    init(isolation: isolated (any Actor)? = #isolation)
    {
        self.isolation = isolation
    }

    public func append(_ object: ChangedObject?)
    {
        guard let object else { return }
        changes.append(object)
    }
    
    public func append(_ objects: [ChangedObject])
    {
        changes.append(contentsOf: objects)
    }
}

public struct FrozenChangeset: Sendable
{
    let changes: [ChangedObject]
    
    public init(changes: [ChangedObject])
    {
        self.changes = changes
    }
}
