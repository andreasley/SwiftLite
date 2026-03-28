import Foundation

/// Represents a single log entry in the database history
public struct LogEntry: Equatable, Hashable, Sendable, Codable
{
    public let id: UUID
    public let timestamp: Date
    public let transactionId: UUID
    public let operationType: OperationType
    public let tableName: String
    public let objectId: UUID?
    public let columnName: String?
    public let newValue: SQLValue?
    public let metadata: String? // JSON-encoded additional data
    public let user: String?
    public let synchronizedIndex: Int64?
    
    public init(
        id: UUID = UUID.v7(),
        timestamp: Date = Date(),
        transactionId: UUID,
        operationType: OperationType,
        tableName: String,
        objectId: UUID? = nil,
        columnName: String? = nil,
        newValue: SQLValue? = nil,
        metadata: String? = nil,
        user: String? = nil,
        synchronizedIndex: Int64? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.transactionId = transactionId
        self.operationType = operationType
        self.tableName = tableName
        self.objectId = objectId
        self.columnName = columnName
        self.newValue = newValue
        self.metadata = metadata
        self.user = user
        self.synchronizedIndex = synchronizedIndex
    }
}
