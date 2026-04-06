import Foundation

public extension Database
{
    enum Error: LocalizedError, Sendable, Equatable {
        case queryFailed(sqlStatement: SQLStatement, status: SQLiteStatus, errorMessage: String)
        case failedToOpen(SQLiteStatus)
        case failedToClose(SQLiteStatus)
        case failedToFindReferencedObject(table: String, id: UUID)
        case notAFileUrl(URL)
        case failedToFindStatement
        case sqliteError(code: Int32)
        case failedToFindResultValue
        case failedToFindReadTransaction
        case failedToMigrateSchema
        case unexpectedStatementValuesForRun

        public var errorDescription: String? {
            return switch self {
            case .queryFailed(let configuration, let status, let errorMessage):
                "Query `\(configuration.text)` failed: \(status.description) (\(errorMessage))"
            case .failedToOpen(let status):
                "Failed to open database: \(status.description))"
            case .failedToClose(let status):
                "Failed to close database: \(status.description)"
            case .notAFileUrl(let url):
                "URL \(url) is not a file URL"
            case .failedToFindReferencedObject(table: let table, id: let id):
                "Failed to find referenced object of type \(table) with id \(id)"
            case .failedToFindStatement:
                "Failed to find the SQLite statement pointer"
            case .sqliteError(code: let code):
                "SQLite error: \(SQLiteStatus(rawValue: code)?.description ?? "Code \(code)")"
            case .failedToFindResultValue:
                "Failed to find result value"
            case .failedToFindReadTransaction:
                "Failed to find a read transaction"
            case .failedToMigrateSchema:
                "Failed to migrate schema"
            case .unexpectedStatementValuesForRun:
                "The SQL statement passed to run unexpectedly contained values"
            }
        }
    }
}

