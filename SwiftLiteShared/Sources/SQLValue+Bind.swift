import SQLite3

public nonisolated extension SQLValue
{
    func bind(to stmt: OpaquePointer?, at index: Int32)
    {
        switch self {
        case .int(let int):
            sqlite3_bind_int64(stmt, index, int)
        case .double(let double):
            sqlite3_bind_double(stmt, index, double)
        case .string(let string):
            sqlite3_bind_text(stmt, index, string, -1, SQLITE_TRANSIENT)
        case .data(let data):
            data.withUnsafeBytes { bytes in
                _ = sqlite3_bind_blob(stmt, index, bytes.baseAddress, Int32(data.count), SQLITE_TRANSIENT)
            }
        case .null:
            sqlite3_bind_null(stmt, index)
        }
    }
}
