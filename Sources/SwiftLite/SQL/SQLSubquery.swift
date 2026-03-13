public nonisolated struct SQLSubquery
{
    let subqueryStatement: SQLStatement
    public let text: String
    
    init(field: String, in subqueryStatement: SQLStatement)
    {
        self.subqueryStatement = subqueryStatement
        self.text = "\(field) IN (\(subqueryStatement.text))"
    }
}

nonisolated extension SQLSubquery: SQLExpression
{
    public var values: [SQLValue] { subqueryStatement.values ?? [] }
}
