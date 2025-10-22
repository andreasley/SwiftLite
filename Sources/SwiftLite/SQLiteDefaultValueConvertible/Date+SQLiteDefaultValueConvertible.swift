#if canImport(Foundation)
import Foundation

extension Date: SQLiteDefaultValueConvertible
{
    public var asDefaultValueString: String { String(self.storageValue) }
}
#endif
