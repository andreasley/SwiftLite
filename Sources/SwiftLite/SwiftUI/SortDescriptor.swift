import Foundation

public struct SortDescriptor<T>: AnySortDescriptor
{
    public enum Order {
        case ascending
        case descending
        
        var sqlKeyword: String {
            switch self {
            case .ascending: return "ASC"
            case .descending: return "DESC"
            }
        }
    }
    
    let keyPath: PartialKeyPath<T>
    let order: Order
    
    public init(_ keyPath: KeyPath<T, some Any>, order: Order = .ascending)
    {
        self.keyPath = keyPath
        self.order = order
    }
    
    public func toSQL() -> SQLSortClause?
    {
        let keyPathString = String(describing: keyPath)
        let components = keyPathString.components(separatedBy: ".")
        guard let propertyName = components.last else {
            fatalError("Invalid keyPath for SortDescriptor")
        }
        return SQLSortClause(text: "\"\(propertyName)\" \(order.sqlKeyword)")
    }
}

public protocol AnySortDescriptor: SQLSortClauseConvertible {}

extension Array: SQLSortClauseConvertible where Element == any AnySortDescriptor
{
    public func toSQL() -> SQLSortClause?
    {
        SQLSortClause(joining: self)
    }
}
