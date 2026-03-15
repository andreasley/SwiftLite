import Foundation

public nonisolated protocol RelationshipModelSchema<Parent, Element>: ModelSchema
{
    associatedtype Parent: SwiftLite.Model
    associatedtype Element: SwiftLite.Model
    
    typealias Columns = RelationshipModelSchemaDefaults.Columns
    typealias Indexes = RelationshipModelSchemaDefaults.Indexes

    static var deletionPolicy: DeletionPolicy { get }
}

public extension RelationshipModelSchema
{
    static var related: [any ModelSchema.Type] {
        [Parent.Schema.self, Element.Schema.self]
    }
}

public nonisolated enum RelationshipModelSchemaDefaults
{
    public static func getTable(name: String, parentTable: String, elementTable: String) -> RequiredSchema.Table
    {
        RequiredSchema.Table(name: name, columns: [
            Columns.id,
            Columns.parent,
            Columns.element,
        ], indexes: [
            Indexes.idx_parent,
            Indexes.idx_element,
        ], foreignKeys: [
            RequiredSchema.ForeignKey(column: "parent", referencedTable: parentTable),
            RequiredSchema.ForeignKey(column: "element", referencedTable: elementTable),
        ])
    }
    
    public nonisolated struct Columns
    {
        static let id = RequiredSchema.Column(name: "id", type: UUID.self)
        static let parent = RequiredSchema.Column(name: "parent", type: UUID.self)
        static let element = RequiredSchema.Column(name: "element", type: UUID.self)
    }
    
    public nonisolated struct Indexes
    {
        static let idx_parent = RequiredSchema.Index(name: "idx_parent", isUnique: false, columns: [Columns.parent])
        static let idx_element = RequiredSchema.Index(name: "idx_element", isUnique: false, columns: [Columns.element])
    }
}
