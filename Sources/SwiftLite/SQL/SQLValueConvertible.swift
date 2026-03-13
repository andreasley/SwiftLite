import Foundation

public nonisolated protocol SQLValueConvertible
{
    func convertToSQLValue() -> SQLValue
    init(db: Database, sqlValue: SQLValue) async throws
}

public nonisolated extension StorageConvertible.Integer
{
    init(db: Database, sqlValue: SQLValue) async throws
    {
        guard case .int(let int) = sqlValue else { throw StorageConvertible.ConversionError.failedToConvert }
        try self.init(storageValue: int)
    }
    
    func convertToSQLValue() -> SQLValue {
        .int(self.storageValue)
    }
}

public nonisolated extension StorageConvertible.Text
{
    init(db: Database, sqlValue: SQLValue) async throws
    {
        guard case .string(let string) = sqlValue else { throw StorageConvertible.ConversionError.failedToConvert }
        try self.init(storageValue: string)
    }

    func convertToSQLValue() -> SQLValue {
        .string(self.storageValue)
    }
}

public nonisolated extension StorageConvertible.Blob
{
    init(db: Database, sqlValue: SQLValue) async throws
    {
        guard case .data(let data) = sqlValue else { throw StorageConvertible.ConversionError.failedToConvert }
        try self.init(storageValue: data)
    }

    func convertToSQLValue() -> SQLValue {
        .data(self.storageValue)
    }
}

public nonisolated extension StorageConvertible.Real
{
    init(db: Database, sqlValue: SQLValue) async throws
    {
        guard case .double(let double) = sqlValue else { throw StorageConvertible.ConversionError.failedToConvert }
        try self.init(storageValue: double)
    }

    func convertToSQLValue() -> SQLValue {
        .double(self.storageValue)
    }
}

public nonisolated extension Fetchable
{
    init(db: Database, sqlValue: SQLValue) async throws
    {
        let id: UUID = try await .init(db: db, sqlValue: sqlValue)
        let result = try await db.get(Self.self, id: id)
        guard let result else { throw Database.Error.failedToFindReferencedObject(table: Self.Model.Schema.table.name, id: id)}
        self = result
    }

    func convertToSQLValue() -> SQLValue {
        .string(id.uuidString)
    }
}

nonisolated extension Optional: SQLValueConvertible where Wrapped: SQLValueConvertible
{
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
