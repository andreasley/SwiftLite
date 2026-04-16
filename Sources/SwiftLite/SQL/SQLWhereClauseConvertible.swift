public protocol SQLWhereClauseConvertible
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

public extension SQLWhereClauseConvertible where Self == SQLWhereClause
{
    static func field(_ field: String, equals value: SQLValueConvertible) -> SQLWhereClause
    {
        SQLWhereClause(field: field, equals: value)
    }

    static func field(_ field: String, contains substring: String) -> SQLWhereClause
    {
        SQLWhereClause(field: field, like: substring)
    }

    static func field(_ field: String, isNull: Bool) -> SQLWhereClause
    {
        SQLWhereClause(field: field, isNull: isNull)
    }

    static func field(_ field: String, in values: [SQLValueConvertible]) -> SQLWhereClause
    {
        SQLWhereClause(field: field, in: values)
    }
}
