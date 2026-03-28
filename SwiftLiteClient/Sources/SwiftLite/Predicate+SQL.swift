import Foundation

extension Predicate
{
    struct SQLWhereClause: SQLExpression
    {
        let text: String
        let values: [SQLValue]
    }
    
    func toSQL() -> SQLWhereClause where repeat (each Input): QueryProxy
    {
        let expression = self.expression
        var parameters: [SQLValue] = []
        
        func visitExpression(_ expr: any StandardPredicateExpression<Bool>) -> String {
            let mirror = Mirror(reflecting: expr)
            let typeName = String(describing: type(of: expr))
            
            // Handle Disjunction (OR) - Check this FIRST before Conjunction
            if typeName.contains("Disjunction") {
                if let lhs = mirror.children.first(where: { $0.label == "lhs" })?.value as? any StandardPredicateExpression<Bool>,
                   let rhs = mirror.children.first(where: { $0.label == "rhs" })?.value as? any StandardPredicateExpression<Bool> {
                    let lhsSQL = visitExpression(lhs)
                    let rhsSQL = visitExpression(rhs)
                    return "(\(lhsSQL) OR \(rhsSQL))"
                }
            }
            
            // Handle Conjunction (AND)
            if typeName.contains("Conjunction") {
                if let lhs = mirror.children.first(where: { $0.label == "lhs" })?.value as? any StandardPredicateExpression<Bool>,
                   let rhs = mirror.children.first(where: { $0.label == "rhs" })?.value as? any StandardPredicateExpression<Bool> {
                    let lhsSQL = visitExpression(lhs)
                    let rhsSQL = visitExpression(rhs)
                    return "(\(lhsSQL) AND \(rhsSQL))"
                }
            }
            
            // Handle String.contains() - special case for LIKE
            if typeName.contains("Contains") || typeName.contains("StringContainsSubstring") {
                var propertyName: String?
                var searchValue: String?
                
                for child in mirror.children {
                    if child.label == "base" || child.label == "root" || child.label == "receiver" {
                        // Use Mirror to extract property name instead of casting to specific generic type
                        let childMirror = Mirror(reflecting: child.value)
                        for kpChild in childMirror.children {
                            if kpChild.label == "keyPath" {
                                if let kp = kpChild.value as? AnyKeyPath {
                                    let keyPathString = String(describing: kp)
                                    let components = keyPathString.components(separatedBy: ".")
                                    if let last = components.last {
                                        propertyName = last
                                    }
                                }
                            }
                        }
                    }
                    
                    if child.label == "other" || child.label == "substring" || child.label == "argument" {
                        // Extract value using Mirror
                        let valueMirror = Mirror(reflecting: child.value)
                        for valueChild in valueMirror.children {
                            if valueChild.label == "value" {
                                searchValue = valueChild.value as? String
                            }
                        }
                    }
                }
                
                if let propertyName = propertyName, let searchValue = searchValue {
                    parameters.append(.string("%\(searchValue)%"))
                    return "\(propertyName) LIKE ?"
                }
            }
            
            // Generic handling for comparison operators using Mirror
            if typeName.contains("Equal") || typeName.contains("NotEqual") || typeName.contains("Comparison") {
                var propertyName: String?
                var value: SQLValue?
                var operatorString = "="
                
                // Check if it's NotEqual
                if typeName.contains("NotEqual") {
                    operatorString = "!="
                }
                
                // Extract lhs (keypath) and rhs (value)
                for child in mirror.children {
                    if child.label == "lhs" {
                        // Try to extract property name from any KeyPath type
                        let childMirror = Mirror(reflecting: child.value)
                        for kpChild in childMirror.children {
                            if kpChild.label == "keyPath" {
                                if let kp = kpChild.value as? AnyKeyPath {
                                    let keyPathString = String(describing: kp)
                                    let components = keyPathString.components(separatedBy: ".")
                                    if let last = components.last {
                                        propertyName = last
                                    }
                                }
                            }
                        }
                    }
                    
                    if child.label == "rhs" {
                        // Extract value from Value<T> expression
                        let valueMirror = Mirror(reflecting: child.value)
                        for valueChild in valueMirror.children {
                            if valueChild.label == "value" {
                                if let sqlConvertible = valueChild.value as? SQLValueConvertible {
                                    value = sqlConvertible.convertToSQLValue()
                                }
                            }
                        }
                    }
                    
                    // For Comparison type, extract the operator
                    if child.label == "op",
                       let op = child.value as? PredicateExpressions.ComparisonOperator {
                        operatorString = getComparisonOperator(op)
                    }
                }
                
                if let propertyName = propertyName, let value = value {
                    parameters.append(value)
                    return "\(propertyName) \(operatorString) ?"
                }
            }
            
            // Fallback: print what we couldn't handle for debugging
            print("UNSUPPORTED: \(typeName)")
            for child in mirror.children {
                print("  - \(child.label ?? "unlabeled"): \(type(of: child.value))")
            }
            
            return "UNSUPPORTED_EXPRESSION"
        }
        
        func extractPropertyName<Root, Value>(from keyPath: PredicateExpressions.KeyPath<PredicateExpressions.Variable<Root>, Value>) -> String {
            let mirror = Mirror(reflecting: keyPath)
            
            for child in mirror.children {
                if child.label == "keyPath" {
                    if let kp = child.value as? PartialKeyPath<Root> {
                        let keyPathString = String(describing: kp)
                        let components = keyPathString.components(separatedBy: ".")
                        if let last = components.last {
                            return last
                        }
                    }
                }
            }
            return "unknown"
        }
        
        func extractValue<Value>(from value: PredicateExpressions.Value<Value>) -> Any {
            let mirror = Mirror(reflecting: value)
            for child in mirror.children {
                if child.label == "value" {
                    return child.value
                }
            }
            return ""
        }
        
        func getComparisonOperator(_ op: PredicateExpressions.ComparisonOperator) -> String {
            switch op {
            case .lessThan: return "<"
            case .lessThanOrEqual: return "<="
            case .greaterThan: return ">"
            case .greaterThanOrEqual: return ">="
            @unknown default: return "="
            }
        }
        
        let whereClause = visitExpression(expression)
        return SQLWhereClause(text: whereClause, values: parameters)
    }
}
