public protocol InitializableFromResultRow
{
    init(row: SQLiteQueryResult, db: Database) throws
}
