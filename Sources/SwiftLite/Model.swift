import Foundation

public protocol Model: InitializableFromResultRow
{
    associatedtype Snapshot: InitializableFromResultRow
    associatedtype FlatSnapshot: InitializableFromResultRow
    
    var db: Database { get }
    var id: UUID { get }
    static var table: Schema.Table { get }
    static var __defaultSelectStatement: String { get }
}

extension Model
{
    public func refresh() async throws
    {
        // TODO: Implement
        fatalError("Not implemented")
    }
    
    public func snapshot() async throws -> Snapshot
    {
        // TODO: Implement
        fatalError("Not implemented")
    }
    
    public func save() async throws
    {
        try await db.save(self)
    }
    
    public func revert() async throws
    {
        // TODO: Implement
        fatalError("Not implemented")
    }
}

protocol AnyPropertyChange
{
    
}

struct PropertyChange<T: Model, V>: @unchecked Sendable, AnyPropertyChange
{
    let date = Date.now
    let id = UUID()
    let keyPath: WritableKeyPath<T, V>
    let value: V
}

public class ObjectChangelog<T: Model>
{
    typealias Model = T
    
    var changes = [PartialKeyPath<Model>: AnyPropertyChange]()
    
    public init() {}
    
    public func log<V>(keyPath: WritableKeyPath<T, V>, value: V)
    {
        let change = PropertyChange(keyPath: keyPath, value: value)
        changes[keyPath] = change
    }
}
