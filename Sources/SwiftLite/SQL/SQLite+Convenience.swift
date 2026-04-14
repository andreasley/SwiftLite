import SQLite3

struct SQLiteDatabase
{
    let databaseHandle: OpaquePointer
}

extension SQLiteDatabase
{
    enum Error: Swift.Error {
        case failedToPrepareStatement(String)
        case failedToStep(String)
    }
}

extension SQLiteDatabase
{
    var lastErrorMessage: String
    {
        String(cString: sqlite3_errmsg(databaseHandle))
    }
    
    func run(sql: String) throws -> Int32
    {
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(databaseHandle, sql, -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        
        guard let statement, prepareResult == SQLiteStatus.ok else {
            throw Error.failedToPrepareStatement(lastErrorMessage)
        }
        
        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_DONE else {
            throw Error.failedToStep(lastErrorMessage)
        }
        
        let changedRows = sqlite3_changes(databaseHandle)
        return changedRows
    }
}
