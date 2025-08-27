import Foundation

public protocol FetchableObject: StorageConvertible.Text
{
    var id: UUID { get }
}

extension FetchableObject
{
     var createTableStatement: String {
         // TODO
         return ""
     }
 }
