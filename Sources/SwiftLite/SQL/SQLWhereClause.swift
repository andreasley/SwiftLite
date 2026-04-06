public nonisolated struct SQLWhereClause: SQLExpression
{
    public let text: String
    public let values: [SQLValue]
    
    public init(text: String, values: [SQLValue])
    {
        self.text = text
        self.values = values
    }
    
    public init(field: String, equals value: SQLValueConvertible)
    {
        self.text = "\(field) = ?"
        self.values = [value.convertToSQLValue()]
    }

    public init(field: String, like string: String)
    {
        self.text = "\(field) LIKE ?"
        self.values = [.string("%\(string)%")]
    }

    public init(field: String, in values: [SQLValueConvertible])
    {
        self.text = "\(field) IN (\(values.map { _ in "?" }.joined(separator: ", ")))"
        self.values = values.map { $0.convertToSQLValue() }
    }
}

public nonisolated extension SQLWhereClause
{
    static let returnNoResults = SQLWhereClause(text: "0", values: [])
}

public nonisolated extension SQLWhereClause
{
    init?(joining clauses: [SQLWhereClause]) throws
    {
        guard !clauses.isEmpty else { return nil }
        if clauses.count == 1 { self = clauses.first!; return }
        self.text = clauses.map { "(\($0.text))" }.joined(separator: " AND ")
        self.values = clauses.flatMap(\.values)
    }

    init?(joining convertibles: [any SQLWhereClauseConvertible]) throws
    {
        let clauses = try convertibles.map { try $0.toSQL() }
        try self.init(joining: clauses)
    }
}

