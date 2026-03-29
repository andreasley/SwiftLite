import Foundation

public struct SortDescriptor<Q>: AnySortDescriptor where Q: QueryProxy
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
    
    let keyPath: PartialKeyPath<Q>
    let order: Order
    
    public init(_ keyPath: KeyPath<Q, some Any>, order: Order = .ascending)
    {
        self.keyPath = keyPath
        self.order = order
    }
    
    func toSQL() -> String
    {
        let keyPathString = String(describing: keyPath)
        let components = keyPathString.components(separatedBy: ".")
        guard let propertyName = components.last else {
            fatalError("Invalid keyPath for SortDescriptor")
        }
        return "\(propertyName) \(order.sqlKeyword)"
    }
}

protocol AnySortDescriptor
{
    func toSQL() -> String
}

extension Array where Element: AnySortDescriptor
{
    func toSQL() -> String
    {
        guard !isEmpty else { return "" }
        return map { $0.toSQL() }.joined(separator: ", ")
    }
}
