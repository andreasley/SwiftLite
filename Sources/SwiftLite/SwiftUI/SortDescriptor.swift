import Foundation

public struct SortDescriptor: AnySortDescriptor
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
    
    let field: String
    let order: Order
    
    public init(_ field: String, order: Order = .ascending)
    {
        self.field = field
        self.order = order
    }
    
    public func toSQL() -> SQLSortClause?
    {
        return SQLSortClause(text: "\"\(field)\" \(order.sqlKeyword)")
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
