public nonisolated struct SQLSortClause
{
    public let text: String
}

public nonisolated extension SQLSortClause
{
    init(joining clauses: [SQLSortClause])
    {
        self.text = clauses.map { "(\($0.text))" }.joined(separator: ", ")
    }

    init(joining convertibles: [SQLSortClauseConvertible])
    {
        self.init(joining: convertibles.map { $0.toSQL() })
    }
}

public nonisolated protocol SQLSortClauseConvertible
{
    func toSQL() -> SQLSortClause
}

extension SQLSortClause: SQLSortClauseConvertible
{
    public func toSQL() -> SQLSortClause
    {
        self
    }
}
