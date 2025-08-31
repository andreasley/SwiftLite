public protocol InitializableFromResultRow
{
    init(row: SQLiteQueryResult) throws
}
