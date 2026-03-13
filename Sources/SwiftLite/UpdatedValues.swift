import Foundation

// Used to record changes to editable objects before saving
@Observable
public nonisolated class UpdatedValues
{
    typealias FieldName = String
    
    private var changes = [FieldName: Change]()
    
    public var hasChanges: Bool {
        changes.count > 0
    }
    
    public func log(field: String, value: SQLValueConvertible)
    {
        let change = Change(field: field, value: value.convertToSQLValue())
        changes[field] = change
    }

    func hasChange(for field: String) -> Bool
    {
        changes[field] != nil
    }
    
    public nonisolated class Change
    {
        let field: String
        let value: SQLValue
        
        var transactionId: UUID? = nil
        
        init(field: String, value: SQLValue)
        {
            self.field = field
            self.value = value
        }
    }
}

nonisolated extension UpdatedValues
{
    public func getChangeset() throws -> [String: SQLValue]?
    {
        guard changes.count > 0 else { return nil }
        let transaction = try DatabaseTask.getWriteTransaction()
        changes.forEach { $0.value.transactionId = transaction.id }
        return changes.compactMapValues { $0.value }
    }
    
    public func didProcessChangeset(success: Bool, transaction: DatabaseTask.WriteTransaction)
    {
        if success {
            changes = changes.filter { $0.value.transactionId != transaction.id }
        } else {
            changes.forEach { $0.value.transactionId = nil }
        }
    }
}

