#if canImport(Foundation)
import Foundation

// Store `Decimal` as an Int64 (preserving four decimal places). This way it's possible to store the value in an `INTEGER` column (rather than `TEXT`) and keep the ability to INDEX and ORDER.
extension Decimal: StorageConvertible.Integer
{
    static var decimalPlaces: Int { 4 }
    
    public var storageValue: Int64 {
        // TODO: Throw if the value is outside of the supported range?
        let multiplier = Decimal(sign: .plus, exponent: Self.decimalPlaces, significand: 1)
        let scaled = self * multiplier
        return Int64(truncating: scaled as NSNumber)
    }
    
    public init(storageValue: Int64)
    {
        let divisor = Decimal(sign: .plus, exponent: Self.decimalPlaces, significand: 1)
        self = Decimal(storageValue) / divisor
    }
}
#endif
