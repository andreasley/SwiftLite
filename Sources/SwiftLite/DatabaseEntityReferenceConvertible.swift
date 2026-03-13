import Foundation

public nonisolated protocol DatabaseEntityReferenceConvertible<Model>
{
    associatedtype Model: SwiftLite.Model
    associatedtype Metadata: DatabaseEntityMetadata
    
    var _metadata: Metadata { get }
}


