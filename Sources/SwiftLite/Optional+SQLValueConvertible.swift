nonisolated extension Optional: SQLValueConvertible where Wrapped: SQLValueConvertible
{
    public static var storageClass: StorageClass { Wrapped.storageClass }

    public init(db: Database, sqlValue: SQLValue) async throws
    {
        guard sqlValue != .null else {
            self = .none
            return
        }
        let result = try await Wrapped.init(db: db, sqlValue: sqlValue)
        self = .some(result)
    }

    public func convertToSQLValue() -> SQLValue {
        if let self {
            return self.convertToSQLValue()
        } else {
            return .null
        }
    }
}
