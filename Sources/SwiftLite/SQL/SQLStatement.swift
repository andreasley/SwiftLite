public struct SQLStatement: Equatable, Hashable, Sendable
{
    let text: String
    let values: [SQLValue]?
    
    public init(text: String, values: [SQLValue]? = nil)
    {
        self.text = text
        self.values = values
    }
}

