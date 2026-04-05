import Foundation

public enum StorageConversionError: Swift.Error {
    case invalidPrimaryKey
    case failedToConvert
    case unexpectedNull
    case valueOutsideConvertibleRange
}

public nonisolated protocol Storable<StorageValue>: SQLValueConvertible
{
    associatedtype StorageValue
    static var fallbackValue: Self? { get }

    init(storageValue: StorageValue) throws
    init(sqlValue: SQLValue) throws
    var storageValue: StorageValue { get }
}

public nonisolated extension Storable
{
    static var fallbackValue: Self? { nil }

    init(db: Database, sqlValue: SQLValue) async throws
    {
        try self.init(sqlValue: sqlValue)
    }
}

public nonisolated extension Storable where StorageValue == Int64
{
    static var storageClass: StorageClass { .integer }

    init(sqlValue: SQLValue) throws
    {
        guard case .int(let int) = sqlValue else { throw StorageConversionError.failedToConvert }
        try self.init(storageValue: int)
    }
    
    func convertToSQLValue() -> SQLValue
    {
        .int(self.storageValue)
    }
}

public nonisolated extension Storable where StorageValue == String
{
    static var storageClass: StorageClass { .text }

    init(sqlValue: SQLValue) throws
    {
        guard case .string(let string) = sqlValue else { throw StorageConversionError.failedToConvert }
        try self.init(storageValue: string)
    }
    
    func convertToSQLValue() -> SQLValue
    {
        .string(self.storageValue)
    }
}

public nonisolated extension Storable where StorageValue == Data
{
    static var storageClass: StorageClass { .blob }

    init(sqlValue: SQLValue) throws
    {
        guard case .data(let data) = sqlValue else { throw StorageConversionError.failedToConvert }
        try self.init(storageValue: data)
    }
    
    func convertToSQLValue() -> SQLValue
    {
        .data(self.storageValue)
    }
}

public nonisolated extension Storable where StorageValue == Double
{
    static var storageClass: StorageClass { .real }

    init(sqlValue: SQLValue) throws
    {
        guard case .double(let double) = sqlValue else { throw StorageConversionError.failedToConvert }
        try self.init(storageValue: double)
    }
    
    func convertToSQLValue() -> SQLValue
    {
        .double(self.storageValue)
    }
}
