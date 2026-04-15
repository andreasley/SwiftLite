import Foundation

// Used to record changes to editable objects before saving
@Observable
public class UpdatedValues
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
    
    public class Change
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
        let associatedData = try WriteAssociatedData.getCurrent()
        changes.forEach { $0.value.transactionId = associatedData.transactionId }
        return changes.compactMapValues { $0.value }
    }
    
    public func didProcessChangeset(success: Bool, transactionId: UUID)
    {
        if success {
            changes = changes.filter { $0.value.transactionId != transactionId }
        } else {
            changes.forEach { $0.value.transactionId = nil }
        }
    }
}

