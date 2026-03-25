import Foundation

extension Array: Storable, SQLValueConvertible where Element: Codable
{
    public typealias Value = String

    public init(storageValue: String) throws
    {
        self = try JSONDecoder().decode(Self.self, from: Data(storageValue.utf8))
    }
    
    public var storageValue: String
    {
        guard let data = try? JSONEncoder().encode(self), let string = String(data: data, encoding: .utf8) else {
            // This isn't great – it's possible that some `Codable` fails to be encoded and values are just silently omitted if that happens.
            // There's no easy way to fix this though, since throwing here would necessitate a lot of changes.
            // TODO: Find a better solution.
            return ""
        }
        return string
    }
}
