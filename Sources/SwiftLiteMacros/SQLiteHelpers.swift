import Foundation

struct SQLiteHelpers
{
    static let reservedWords = Set([
        "table", "index", "select", "from", "where", "insert", "update", "delete", "create", "drop", "alter", "database", "schema", "view", "trigger", "primary", "foreign", "key", "constraint", "unique", "not", "null", "default", "check", "references", "on", "cascade", "restrict", "union", "intersect", "except", "order", "by", "group", "having", "limit", "offset", "join", "inner", "left", "right", "outer", "as", "distinct", "all", "exists", "in", "between", "like", "and", "or", "case", "when", "then", "else", "end"
    ])

    static let allowedCharactersForTableNames = Set("abcdefghijklmnopqrstuvwxyz0123456789_")

    static func generateTableName(_ segments: [String]) throws -> String
    {
        enum Error: Swift.Error, CustomStringConvertible {
            case nameIsEmpty

            var description: String {
                switch self {
                case .nameIsEmpty:
                    return "Generated table name is empty"
                }
            }
        }
        
        let sanitizedSegments = segments.map { segment in
            var output = ""
            var previousCharWasLowercase = false
            
            for char in segment {
                let lowercasedChar: Character
                if char.isUppercase {
                    if !segment.isEmpty && previousCharWasLowercase {
                        output += "_"
                    }
                    lowercasedChar = char.lowercased().first ?? char
                    previousCharWasLowercase = false
                } else {
                    lowercasedChar = char
                    previousCharWasLowercase = char.isLowercase
                }
                
                if allowedCharactersForTableNames.contains(lowercasedChar) {
                    output += String(lowercasedChar)
                } else {
                    output += lowercasedChar.unicodeScalars.map({"u\(String($0.value, radix: 16))"}).joined()
                }
            }
            return output
        }
        
        var fullName = sanitizedSegments.joined(separator: "__")
        
        guard let firstChar = fullName.first else {
            throw Error.nameIsEmpty
        }

        if firstChar.isNumber {
            fullName = "t_" + fullName
        }
        
        if reservedWords.contains(fullName) {
            fullName = fullName + "_table"
        }
                
        return fullName
    }
}
