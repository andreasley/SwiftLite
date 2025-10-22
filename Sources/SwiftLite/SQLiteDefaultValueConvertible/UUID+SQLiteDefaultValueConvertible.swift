#if canImport(Foundation)
import Foundation

extension UUID: SQLiteDefaultValueConvertible
{
    public var asDefaultValueString: String { "'" + self.uuidString + "'" }
}
#endif
