import Foundation

public nonisolated struct ChangedObject: Sendable
{
    let table: String
    let objectId: UUID
    let status: Status
    let updatedFields: [String: SQLValue]?
    let transactionId: UUID

    public nonisolated enum Status: Sendable {
        case created
        case deleted
        case updated
    }
}
