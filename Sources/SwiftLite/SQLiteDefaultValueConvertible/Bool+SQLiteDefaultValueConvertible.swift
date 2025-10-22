extension Bool: SQLiteDefaultValueConvertible
{
    public var asDefaultValueString: String { self ? "1" : "0" }
}
