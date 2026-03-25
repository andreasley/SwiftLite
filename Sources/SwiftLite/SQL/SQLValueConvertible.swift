import Foundation

public nonisolated protocol SQLValueConvertible: SendableMetatype
{
    static var storageClass: StorageClass { get }

    func convertToSQLValue() -> SQLValue
    init(db: Database, sqlValue: SQLValue) async throws
}

