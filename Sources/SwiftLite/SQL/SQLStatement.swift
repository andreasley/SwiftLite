public nonisolated struct SQLStatement: Equatable, Hashable, Sendable
{
    let text: String
    let values: [SQLValue]?
    
    init(text: String, values: [SQLValue]? = nil)
    {
        self.text = text
        self.values = values
    }
}

public nonisolated enum SQLStatementPreset
{
    public struct Select: SQLStatementProvider
    {
        let table: String
        let columns: [String]?
        
        public let sqlStatement: SQLStatement
        
        init(table: String, columns: [String]? = nil, conditions: [SQLCondition]? = nil, limit: Int? = nil)
        {
            self.table = table
            self.columns = columns
            
            var values: [SQLValue]?
            
            var text = "SELECT \(columns?.joined(separator: ", ") ?? "*") FROM \(table)"
            if let conditions, conditions.count > 0 {
                let conditionsText = conditions.map(\.text).joined(separator: " AND ")
                values = conditions.map(\.value)
                text += " WHERE \(conditionsText)"
            }

            if let limit {
                text += " LIMIT \(limit)"
            }

            self.sqlStatement = SQLStatement(text: text, values: values)
        }

        init(table: String, columns: [String]? = nil, conditions expression: any SQLExpression, limit: Int? = nil)
        {
            self.table = table
            self.columns = columns
            
            let values = expression.values
            var text = "SELECT \(columns?.joined(separator: ", ") ?? "*") FROM \(table) WHERE \(expression.text)"
            
            if let limit {
                text += " LIMIT \(limit)"
            }
            
            self.sqlStatement = SQLStatement(text: text, values: values)
        }
        
        func withConditions(_ expression: any SQLExpression, limit: Int? = nil) -> Self
        {
            .init(table: table, columns: columns, conditions: expression, limit: limit)
        }

        func withCondition(_ condition: SQLCondition, limit: Int? = nil) -> Self
        {
            .init(table: table, columns: columns, conditions: condition, limit: limit)
        }
    }

    public struct Delete: SQLStatementProvider
    {
        let table: String
        
        public let sqlStatement: SQLStatement
        
        init(table: String, conditions: [SQLCondition])
        {
            self.table = table
            
            let conditionsText = conditions.map(\.text).joined(separator: " AND ")
            let values = conditions.map(\.value)
            let text = "DELETE FROM \(table) WHERE \(conditionsText)"

            self.sqlStatement = SQLStatement(text: text, values: values)
        }
    }

    public struct Insert: SQLStatementProvider
    {
        enum ConstraintFailureMode {
            case skip
            case fail
        }
        
        let table: String
        
        public let sqlStatement: SQLStatement
        
        init(table: String, updatedFields: [String: SQLValue], constraintFailureMode: ConstraintFailureMode = .fail)
        {
            self.table = table
            
            var values = [SQLValue]()
            values.append(contentsOf: updatedFields.map(\.value))
            
            let fieldsText = updatedFields.map(\.key).joined(separator: ",")
            let valuesText = Array(repeating: "?", count: updatedFields.count).joined(separator: ",")

            let constraintFailureModeText = constraintFailureMode == .skip ? "OR IGNORE" : ""
            let text = "INSERT \(constraintFailureModeText) INTO \(table) (\(fieldsText)) VALUES (\(valuesText))"
            
            self.sqlStatement = SQLStatement(text: text, values: values)
        }
    }

    public struct Update: SQLStatementProvider
    {
        let table: String
        
        public let sqlStatement: SQLStatement
        
        init(table: String, updatedFields: [String: SQLValue], condition: SQLCondition)
        {
            self.table = table
            
            var values = [SQLValue]()
            values.append(contentsOf: updatedFields.map(\.value))
            values.append(condition.value)
            
            let setterText = updatedFields.map { "\($0.key) = ?" }.joined(separator: ", ")
            
            let text = "UPDATE \(table) SET \(setterText) WHERE \(condition.text)"
            
            self.sqlStatement = SQLStatement(text: text, values: values)
        }
    }

    public struct Pragma: SQLStatementProvider
    {
        let name: String
        public let sqlStatement: SQLStatement
        
        init(name: String)
        {
            self.name = name

            let text = "PRAGMA \(name)"
            
            self.sqlStatement = SQLStatement(text: text)
        }
    }
}
