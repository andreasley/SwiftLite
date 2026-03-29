public nonisolated struct SQLWhereClause: SQLExpression
{
    public let text: String
    public let values: [SQLValue]
}

public nonisolated extension SQLWhereClause
{
    public init(joining clauses: [SQLWhereClause]) throws
    {
        self.text = clauses.map { "(\($0.text))" }.joined(separator: " AND ")
        self.values = clauses.flatMap(\.values)
    }

    public init(joining convertibles: [SQLWhereClauseConvertible]) throws
    {
        let clauses = try convertibles.map { try $0.toSQL() }
        try self.init(joining: clauses)
    }
}

public nonisolated protocol SQLWhereClauseConvertible
{
    func toSQL() throws -> SQLWhereClause
}

extension SQLWhereClause: SQLWhereClauseConvertible
{
    public func toSQL() throws -> SQLWhereClause
    {
        self
    }
}
