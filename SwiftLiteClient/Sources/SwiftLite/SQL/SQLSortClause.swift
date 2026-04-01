public nonisolated struct SQLSortClause
{
    public let text: String
}

public nonisolated extension SQLSortClause
{
    init?(joining clauses: [SQLSortClause])
    {
        guard clauses.count > 1 else { return nil }
        if clauses.count == 1 { self = clauses.first!; return }
        self.text = clauses.map { $0.text }.joined(separator: ", ")
    }

    init?(joining convertibles: [SQLSortClauseConvertible])
    {
        self.init(joining: convertibles.compactMap { $0.toSQL() })
    }
}

public nonisolated protocol SQLSortClauseConvertible
{
    func toSQL() -> SQLSortClause?
}

extension SQLSortClause: SQLSortClauseConvertible
{
    public func toSQL() -> SQLSortClause?
    {
        self
    }
}
