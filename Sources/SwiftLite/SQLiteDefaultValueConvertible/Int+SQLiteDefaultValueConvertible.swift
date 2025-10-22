extension Int: SQLiteDefaultValueConvertible
{
    public var asDefaultValueString: String { String(self) }
}

extension Int8: SQLiteDefaultValueConvertible
{
    public var asDefaultValueString: String { String(self) }
}

extension Int16: SQLiteDefaultValueConvertible
{
    public var asDefaultValueString: String { String(self) }
}

extension Int32: SQLiteDefaultValueConvertible
{
    public var asDefaultValueString: String { String(self) }
}

extension Int64: SQLiteDefaultValueConvertible
{
    public var asDefaultValueString: String { String(self) }
}

extension UInt: SQLiteDefaultValueConvertible
{
    public var asDefaultValueString: String { String(self) }
}

extension UInt8: SQLiteDefaultValueConvertible
{
    public var asDefaultValueString: String { String(self) }
}

extension UInt16: SQLiteDefaultValueConvertible
{
    public var asDefaultValueString: String { String(self) }
}

extension UInt32: SQLiteDefaultValueConvertible
{
    public var asDefaultValueString: String { String(self) }
}

extension UInt64: SQLiteDefaultValueConvertible
{
    public var asDefaultValueString: String { String(self) }
}


@available(macOS 15.0, *)
extension Int128: SQLiteDefaultValueConvertible
{
    public var asDefaultValueString: String { String(self) }
}

@available(macOS 15.0, *)
extension UInt128: SQLiteDefaultValueConvertible
{
    public var asDefaultValueString: String { String(self) }
}
