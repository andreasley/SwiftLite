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

