import Foundation

public struct ChangedObject: Sendable
{
    public enum Status: Sendable {
        case created
        case deleted
        case updated
    }
    
    public let table: String
    public let objectId: UUID
    public let status: Status
    public let updatedFields: [String: SQLValue]?
    public let transactionId: UUID

    public init(table: String, objectId: UUID, status: Status, updatedFields: [String : SQLValue]?, transactionId: UUID)
    {
        self.table = table
        self.objectId = objectId
        self.status = status
        self.updatedFields = updatedFields
        self.transactionId = transactionId
    }
}
