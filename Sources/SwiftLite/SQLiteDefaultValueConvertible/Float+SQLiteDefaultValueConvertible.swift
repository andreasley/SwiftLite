extension Float16: SQLiteDefaultValueConvertible
{
    public var asDefaultValueString: String { String(self) }
}

extension Float32: SQLiteDefaultValueConvertible
{
    public var asDefaultValueString: String { String(self) }
}

extension Float64: SQLiteDefaultValueConvertible
{
    public var asDefaultValueString: String { String(self) }
}
