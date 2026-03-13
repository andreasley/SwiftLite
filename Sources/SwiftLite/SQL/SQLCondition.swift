public nonisolated struct SQLCondition
{
    let field: String
    let value: SQLValue
    public let text: String
    
    init(field: String, value: SQLValue)
    {
        self.field = field
        self.value = value
        self.text = "\(field) = ?"
    }
}

nonisolated extension SQLCondition: SQLExpression
{
    public var values: [SQLValue] { [value] }
}
