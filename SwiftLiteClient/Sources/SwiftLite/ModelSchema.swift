import Foundation

public nonisolated protocol ModelSchema: SendableMetatype
{
    associatedtype Model: SwiftLite.Model
    
    static var table: RequiredSchema.Table { get }
    static var related: [any ModelSchema.Type] { get }
}
