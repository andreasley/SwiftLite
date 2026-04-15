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
    static func field(_ field: String, equals value: SQLValueConvertible) throws -> SQLWhereClause
    {
        SQLWhereClause(field: field, equals: value)
    }

    static func field(_ field: String, isNull: Bool) -> SQLWhereClause
    {
        SQLWhereClause(field: field, isNull: isNull)
    }

    static func field<T, V>(_ keyPath: KeyPath<T, V>, equals value: V) throws -> SQLWhereClause where V: SQLValueConvertible
    {
        guard let propertyPath = keyPath.propertyPath else { throw Database.Error.failedToCreateWhereClause }
        return SQLWhereClause(field: propertyPath, equals: value)
    }
    static func field<T>(_ keyPath: PartialKeyPath<T>, equals value: SQLValueConvertible) throws -> SQLWhereClause
    {
        guard let propertyPath = keyPath.propertyPath else { throw Database.Error.failedToCreateWhereClause }
        return SQLWhereClause(field: propertyPath, equals: value)
    }
    
    static func field<T>(_ keyPath: PartialKeyPath<T>, in values: [SQLValueConvertible]) throws -> SQLWhereClause
    {
        guard let propertyPath = keyPath.propertyPath else { throw Database.Error.failedToCreateWhereClause }
        return SQLWhereClause(field: propertyPath, in: values)
    }
}

private extension PartialKeyPath
{
    var propertyPath: String? {
        let desc = debugDescription.dropFirst() // remove leading `\`
        guard let dotIndex = desc.firstIndex(of: ".") else { return nil }
        return String(desc[desc.index(after: dotIndex)...])
    }
}
