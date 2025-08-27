import Foundation

public protocol Model
{
    var id: UUID { get }
    static var entity: Schema.Entity { get }
}
