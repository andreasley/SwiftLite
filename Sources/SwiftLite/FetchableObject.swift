public protocol FetchableObject
{
//    static var selectStatementFlat: String { get }
    static var entity: Schema.Entity<Self> { get }
}
 extension FetchableObject
{
     var createTableStatement: String {
         // TODO
         return ""
     }
 }
