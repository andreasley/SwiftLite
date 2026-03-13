#if canImport(Foundation)
import Foundation

// SQLite's built-in date/time functions work well with Unix timestamps in milliseconds (see https://sqlite.org/lang_datefunc.html) and it's easy/fast to get these from a `Date`.
// The precision is less than that of `Date`, but that's not an issue for common use-casese.
nonisolated extension Date: StorageConvertible.Integer
{
    public var storageValue: Int64 {
        Int64(timeIntervalSince1970 * 1000)
    }
    
    public init(storageValue: Int64)
    {
        self.init(timeIntervalSince1970: Double(storageValue)/1000)
    }
}
#endif
