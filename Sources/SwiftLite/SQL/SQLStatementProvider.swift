public nonisolated protocol SQLStatementProvider: Equatable, Hashable, Sendable
{
    var sqlStatement: SQLStatement { get }
}
