import Foundation

public protocol Model: InitializableFromResultRow
{
    associatedtype Snapshot: InitializableFromResultRow
    associatedtype FlatSnapshot: InitializableFromResultRow
    
    var id: UUID { get }
    static var table: Schema.Table { get }
    static var __defaultSelectStatement: String { get }
}

extension Model
{
    func refresh() throws
    {
        // TODO: Implement
        fatalError("Not implemented")
    }
    
    func snapshot() -> Snapshot
    {
        // TODO: Implement
        fatalError("Not implemented")
    }
    
    func save() throws
    {
        // TODO: Implement
        fatalError("Not implemented")
    }
    
    func revert() throws
    {
        // TODO: Implement
        fatalError("Not implemented")
    }
}
