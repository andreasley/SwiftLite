import Foundation

public nonisolated struct Query<T: Fetchable>: Sendable, SQLExpression
{
    public typealias Proxy = Queryable<T.Model.QueryProxy>
    
    let predicates: [Proxy.Predicate]
    public let text: String
    public let values: [SQLValue]

    init(_ builder: (Proxy) -> Proxy.Predicate)
    {
        var predicates: [Proxy.Predicate] = []
        predicates.append(builder(Proxy()))

        self.predicates = predicates
        self.text = predicates.map { $0.sql }.joined(separator: " AND ")
        self.values = predicates.flatMap { $0.bindings }
    }
}

public nonisolated protocol WithNamedKeyPaths
{
    static func nameForKeyPath(keyPath: PartialKeyPath<Self>) -> String
}

@dynamicMemberLookup
public nonisolated struct Queryable<QueryProxy: WithNamedKeyPaths>
{
    public subscript<Value>(dynamicMember keyPath: KeyPath<QueryProxy, Value>) -> Expression<Value>
    {
        Expression(keyPath: keyPath)
    }

    // This allows writing `$0.isActive` to check if it is true (if `isActive` is a `Bool`)
    subscript(dynamicMember keyPath: KeyPath<QueryProxy, Bool>) -> Predicate
    {
        Predicate(sql: "\(QueryProxy.nameForKeyPath(keyPath: keyPath)) = ?", bindings: [.int(1)])
    }

    nonisolated public struct Expression<Value> where Value: SQLValueConvertible
    {
        fileprivate let keyPath: KeyPath<QueryProxy, Value>
        
        var columnName: String {
            QueryProxy.nameForKeyPath(keyPath: keyPath)
        }

        static func == (lhs: Self, rhs: Value) -> Predicate
        {
            Predicate(sql: "\(lhs.columnName) = ?", bindings: [rhs.convertToSQLValue()])
        }

        static func > (lhs: Self, rhs: Value) -> Predicate
        {
            Predicate(sql: "\(lhs.columnName) > ?", bindings: [rhs.convertToSQLValue()])
        }

        static func < (lhs: Self, rhs: Value) -> Predicate
        {
            Predicate(sql: "\(lhs.columnName) < ?", bindings: [rhs.convertToSQLValue()])
        }
    }

    public nonisolated struct Predicate: Hashable, Sendable
    {
        let sql: String
        let bindings: [SQLValue]
        
        static func && (lhs: Self, rhs: Self) -> Self
        {
            Predicate(sql: "(\(lhs.sql)) AND (\(rhs.sql))", bindings: lhs.bindings + rhs.bindings)
        }

        static func || (lhs: Self, rhs: Self) -> Self
        {
            Predicate(sql: "(\(lhs.sql)) OR (\(rhs.sql))", bindings: lhs.bindings + rhs.bindings)
        }

        static prefix func ! (predicate: Self) -> Self
        {
            Predicate(sql:"NOT (\(predicate.sql))", bindings: predicate.bindings)
        }
    }
}
