import Foundation

public nonisolated protocol SQLExpression: Hashable, Equatable, Sendable
{
    var text: String { get }
    var values: [SQLValue] { get }
}

public nonisolated extension SQLExpression where Self == SQLWhereClause
{
    static func byId(_ id: UUID) -> SQLWhereClause
    {
        SQLWhereClause(field: "id", equals: id)
    }

    static func byId(in ids: [UUID]) -> SQLWhereClause
    {
        SQLWhereClause(field: "id", in: ids)
    }

    static func byParent(_ id: UUID) -> SQLWhereClause
    {
        SQLWhereClause(field: "parent", equals: id)
    }

    static func byElement(_ id: UUID) -> SQLWhereClause
    {
        SQLWhereClause(field: "element", equals: id)
    }
}
