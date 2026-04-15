import Foundation

public protocol DatabaseEntityMetadata
{
    var db: Database { get }
    var id: UUID { get }
    var lastRead: Date? { get }
}
