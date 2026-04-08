import Foundation

public nonisolated protocol RelationshipModelSchema<Parent, Element>: ModelSchema
{
    associatedtype Parent: SwiftLite.Fetchable
    associatedtype Element: SwiftLite.Fetchable
    
    typealias Columns = RelationshipModelSchemaDefaults.Columns

    static var deletionPolicy: DeletionPolicy { get }
}

public extension RelationshipModelSchema
{
    static var related: [any ModelSchema.Type] {
        [Parent.Model.Schema.self, Element.Model.Schema.self]
    }
}

public nonisolated enum RelationshipModelSchemaDefaults
{
    public static func getTable(name: String, parentTable: String, elementTable: String) -> RequiredSchema.Table
    {
        RequiredSchema.Table(name: name, columns: [
            Columns.id,
            Columns.index,
            Columns.parent(referencedTable: parentTable),
            Columns.element(referencedTable: elementTable),
        ], indexes: [
            RequiredSchema.Index(name: "idx_\(name)_index", isUnique: false, columns: [Columns.index]),
            RequiredSchema.Index(name: "idx_\(name)_parent", isUnique: false, columns: [Columns.parent(referencedTable: parentTable)]),
            RequiredSchema.Index(name: "idx_\(name)_element", isUnique: false, columns: [Columns.element(referencedTable: elementTable)]),
        ])
    }
    
    public nonisolated struct Columns
    {
        static let id = RequiredSchema.Column(name: "id", type: UUID.self, collation: "NOCASE")
        static let index = RequiredSchema.Column(name: "index", type: Int.self)
        static func parent(referencedTable: String) -> RequiredSchema.Column {
            RequiredSchema.Column(name: "parent", type: UUID.self, referencedTable: referencedTable, collation: "NOCASE")
        }
        static func element(referencedTable: String) -> RequiredSchema.Column {
            RequiredSchema.Column(name: "element", type: UUID.self, referencedTable: referencedTable, collation: "NOCASE")
        }
    }
}
