public nonisolated protocol StorableEnum: Storable, Sendable, RawRepresentable where RawValue: Storable
{
    static var fallbackValue: Self { get }
}

public nonisolated extension StorableEnum
{
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
