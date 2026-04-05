public nonisolated protocol InitializableFromResultRowAsync
{
    init(db: Database, row: Database.Row) async throws
}

public nonisolated protocol InitializableFromResultRow
{
    init(db: Database, row: Database.Row) throws
}
