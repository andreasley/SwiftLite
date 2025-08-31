import Foundation

public protocol Model: InitializableFromResultRow
{
    var id: UUID { get }
    static var table: Schema.Table { get }
}
