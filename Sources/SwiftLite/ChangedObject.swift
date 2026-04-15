import Foundation

public struct ChangedObject: Sendable
{
    public let table: String
    public let objectId: UUID
    public let status: Status
    public let updatedFields: [String: SQLValue]?
    public let transactionId: UUID

    public enum Status: Sendable {
        case created
        case deleted
        case updated
    }
}
