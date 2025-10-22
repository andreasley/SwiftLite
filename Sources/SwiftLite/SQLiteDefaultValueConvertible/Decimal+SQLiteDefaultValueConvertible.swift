#if canImport(Foundation)
import Foundation

extension Decimal: SQLiteDefaultValueConvertible
{
    public var asDefaultValueString: String { String(self.storageValue) }
}
#endif
