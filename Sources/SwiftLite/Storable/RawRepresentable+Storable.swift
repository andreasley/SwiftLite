public nonisolated protocol StorableEnum: Storable, Sendable, RawRepresentable, Identifiable where RawValue: Storable, RawValue: Hashable {}

public nonisolated extension StorableEnum
{
    var id: RawValue { rawValue }
    var storageValue: RawValue { rawValue }

    init(storageValue: RawValue) throws
    {
        guard let value = Self.init(rawValue: storageValue) else {
            throw StorageConversionError.failedToConvert
        }
        self = value
    }
    
    init(sqlValue: SQLValue) throws
    {
        guard let rawValue = try? RawValue(sqlValue: sqlValue) else {
            throw StorageConversionError.failedToConvert
        }

        try self.init(storageValue: rawValue)
    }
}


public nonisolated protocol StorableEnumWithFallback: Storable, Sendable, RawRepresentable, Identifiable where RawValue: Storable, RawValue: Hashable
{
    static var fallbackValue: Self { get }
}

public nonisolated extension StorableEnumWithFallback
{
    var id: RawValue { rawValue }
    var storageValue: RawValue { rawValue }

    init(storageValue: RawValue) throws
    {
        self = .init(rawValue: storageValue) ?? Self.fallbackValue
    }
    
    init(sqlValue: SQLValue) throws
    {
        let rawValue = try RawValue(sqlValue: sqlValue)
        try self.init(storageValue: rawValue)
    }
}

