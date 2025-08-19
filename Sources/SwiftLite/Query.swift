struct Query
{
    let selectors: [Target]
    
    struct Target
    {
        let table: String
        let fields: [String]
        let relation: String
    }
}
