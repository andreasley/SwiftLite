import Foundation

public protocol FetchableObject: StorageConvertible.Text
{
//    static var selectStatementFlat: String { get }
    static var entity: Schema.Entity<Self> { get }
    var id: UUID { get }
}

extension FetchableObject
{
     var createTableStatement: String {
         // TODO
         return ""
     }
 }
