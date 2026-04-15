public enum SQLStatementPreset
{
    public struct Select: SQLStatementProvider
    {
        let table: String
        let columnExpression: String
        
        public let sqlStatement: SQLStatement
        
        init(table: String, columnExpression: String, conditions: (any SQLExpression)? = nil, orderBy: String? = nil, limit: Int? = nil)
        {
            self.table = table
            self.columnExpression = columnExpression
            
            var values: [SQLValue]?
            
            var text = "SELECT \(columnExpression) FROM \(table)"
            if let conditions {
                values = conditions.values
                text += " WHERE \(conditions.text)"
            }
            
            if let orderBy, !orderBy.isEmpty {
                text += " ORDER BY \(orderBy)"
            }

            if let limit {
                text += " LIMIT \(limit)"
            }

            self.sqlStatement = SQLStatement(text: text, values: values)
        }

        init(table: String, columns: [String]? = nil, conditions: (any SQLExpression)? = nil, orderBy: String? = nil, limit: Int? = nil)
        {
            self.table = table
            
            var values: [SQLValue]?
            
            let columnExpression = if let columns {
                columns.map({"\"\($0)\""}).joined(separator: ", ")
            } else {
                "*"
            }
            
            self.columnExpression = columnExpression
            
            var text = "SELECT \(columnExpression) FROM \(table)"
            if let conditions {
                values = conditions.values
                text += " WHERE \(conditions.text)"
            }
            
            if let orderBy, !orderBy.isEmpty {
                text += " ORDER BY \(orderBy)"
            }

            if let limit {
                text += " LIMIT \(limit)"
            }

            self.sqlStatement = SQLStatement(text: text, values: values)
        }

        init(table: String, columns: [String]? = nil, conditions expression: any SQLExpression, orderBy: String? = nil, limit: Int? = nil)
        {
            self.table = table
            
            let columnExpression = if let columns {
                columns.map({"\"\($0)\""}).joined(separator: ", ")
            } else {
                "*"
            }
            
            self.columnExpression = columnExpression

            let values = expression.values
            
            var text = "SELECT \(columnExpression) FROM \(table) WHERE \(expression.text)"
            
            if let orderBy, !orderBy.isEmpty {
                text += " ORDER BY \(orderBy)"
            }
            
            if let limit {
                text += " LIMIT \(limit)"
            }
            
            self.sqlStatement = SQLStatement(text: text, values: values)
        }
        
        func withConditions(_ expression: any SQLExpression, orderBy: String? = nil, limit: Int? = nil) -> Self
        {
            .init(table: table, columnExpression: columnExpression, conditions: expression, orderBy: orderBy, limit: limit)
        }

        func withCondition(_ condition: any SQLExpression, orderBy: String? = nil, limit: Int? = nil) -> Self
        {
            .init(table: table, columnExpression: columnExpression, conditions: condition, orderBy: orderBy, limit: limit)
        }
        
        func withOrderBy(_ orderBy: String, limit: Int? = nil) -> Self
        {
            .init(table: table, columnExpression: columnExpression, conditions: nil, orderBy: orderBy, limit: limit)
        }
    }

    public struct Delete: SQLStatementProvider
    {
        let table: String
        
        public let sqlStatement: SQLStatement
        
        init(table: String, conditions: any SQLExpression)
        {
            self.table = table
            
            let values = conditions.values
            let text = "DELETE FROM \(table) WHERE \(conditions.text)"

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
            
            let fieldsText = updatedFields.map(\.key).map({"\"\($0)\""}).joined(separator: ",")
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
        
        init(table: String, updatedFields: [String: SQLValue], condition: any SQLExpression)
        {
            self.table = table
            
            var values = [SQLValue]()
            values.append(contentsOf: updatedFields.map(\.value))
            values.append(contentsOf: condition.values)
            
            let setterText = updatedFields.map { "\"\($0.key)\" = ?" }.joined(separator: ", ")
            
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
