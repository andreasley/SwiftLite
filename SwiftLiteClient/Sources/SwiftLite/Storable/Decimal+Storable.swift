#if canImport(Foundation)
import Foundation

// Store `Decimal` as an Int64 (preserving four decimal places). This way it's possible to store the value in an `INTEGER` column (rather than `TEXT`) and keep the ability to INDEX and ORDER.
// TODO: Make configurable
nonisolated extension Decimal: Storable
{
    public typealias StorageValue = Int64

    static var decimalPlaces: Int { 4 }
    
    public var storageValue: StorageValue {
        // TODO: Throw if the value is outside of the supported range?
        let multiplier = Decimal(sign: .plus, exponent: Self.decimalPlaces, significand: 1)
        let scaled = self * multiplier
        return Int64(truncating: scaled as NSNumber)
    }
    
    public init(storageValue: StorageValue)
    {
        let divisor = Decimal(sign: .plus, exponent: Self.decimalPlaces, significand: 1)
        self = Decimal(storageValue) / divisor
    }
}


//nonisolated extension Decimal: Storable
//{
//    public typealias StorageValue = String
//
//    public var storageValue: StorageValue {
//        self.description
//    }
//    
//    public init(storageValue: StorageValue)
//    {
//        self = (try? Decimal(storageValue, format: .number)) ?? .nan
//    }
//}


#endif
