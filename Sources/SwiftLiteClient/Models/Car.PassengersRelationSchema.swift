import SwiftLite

// Macro prototype for `PassengersRelationSchema`
nonisolated final class PassengersRelationSchemaExample: RelationshipModelSchema
{
    typealias Parent = Car
    typealias Element = Passenger
    
    static let deletionPolicy: DeletionPolicy = .cascade
    
    static let table = RelationshipModelSchemaDefaults.getTable(name: "Car_passengers__Passenger", parentTable: Parent.Schema.table.name, elementTable: Element.Schema.table.name)
}
