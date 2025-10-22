extension String: SQLiteDefaultValueConvertible
{
    public var asDefaultValueString: String { "'" + self + "'" }
}
