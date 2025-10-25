import Foundation

public protocol Model: InitializableFromResultRow
{
    associatedtype Snapshot: InitializableFromResultRow
    associatedtype FlatSnapshot: InitializableFromResultRow
    
    var id: UUID { get }
    static var table: Schema.Table { get }
    static var __defaultSelectStatement: String { get }
}
