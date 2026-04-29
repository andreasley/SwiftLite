import Foundation

// Used to record changes to editable objects before saving
@Observable
public class UpdatedValues
{
    typealias FieldName = String
    
    private var changes = [FieldName: Change]()
    
    public var hasUnsavedChanges: Bool {
        let countOfUnsavedChangesNotInSavingTransaction = changes.count { $0.value.transactionId == nil }
        return countOfUnsavedChangesNotInSavingTransaction > 0
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
    public func getChangeset(isolation: isolated (any Actor)? = #isolation) throws -> [String: SQLValue]?
    {
        let unsavedChanges = changes.filter { $0.value.transactionId == nil }
        guard unsavedChanges.count > 0 else { return nil }
        
        let savingData = try WriteAssociatedData.getSavingData(isolation: isolation)
        unsavedChanges.forEach {
            $0.value.transactionId = savingData.transactionId
        }
        return unsavedChanges.compactMapValues { $0.value }
    }
    
    public func didProcessChangeset(success: Bool, transactionId: UUID)
    {
        if success {
            // Remove saved changes from the pending collection
            changes = changes.filter { $0.value.transactionId != transactionId }
        } else {
            // Mark non-saved changes as not in transaction
            changes.forEach {
                if $0.value.transactionId == transactionId {
                    $0.value.transactionId = nil
                }
            }
        }
    }
}

