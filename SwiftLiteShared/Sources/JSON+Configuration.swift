import Foundation

public extension JSONEncoder
{
    static var forSwiftLiteSync: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }
}

public extension JSONDecoder
{
    static var forSwiftLiteSync: JSONDecoder {
        let encoder = JSONDecoder()
        encoder.dateDecodingStrategy = .millisecondsSince1970
        return encoder
    }
}
