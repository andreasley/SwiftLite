import SwiftLite
import Foundation

@Model class Car
{
//    static let nameYearIndex: IndexGroup
    
//    @Attribute(.readOnly, .unique, index: .single)
//    @Indexed
    let publicId: UUID = UUID() // `let` creates a read-only property
    
//    @Indexed(index: nameYearIndex)
    var name: String
    
//    @Indexed(index: nameYearIndex)
    var year: Int
    
    var manufacturer: Manufacturer?
    
    init(name: String, year: Int)
    {
        self.name = name
        self.year = year
    }
}

class MacroExtendedCar
{
    static let table = "macro_extended_car"
    
    // @PrimaryKey
    let id: UUID
    
    let publicId: UUID

    var name: String = ""
    var year: Int = 0
    var manufacturer: Manufacturer?
    
    private static let entity = Schema.Entity(properties: [
        Schema.Entity.Property(name: "publicId", type: "UUID", isPrimaryKey: false, isUnique: true, isIndexed: false),
        Schema.Entity.Property(name: "name", type: "String", isPrimaryKey: false, isUnique: false, isIndexed: false),
        Schema.Entity.Property(name: "year", type: "Int", isPrimaryKey: false, isUnique: false, isIndexed: false),
    ])
    
    private static let __schemaRegistration: Void = {
        Schema.default.register(entity)
    }()
    
    init(row: SQLiteQueryResult)
    {
        // TODO: Read data from result
        self.id = UUID()
        self.publicId = UUID()
        self.name = ""
        self.year = 0
    }
}

/*
CREATE TABLE IF NOT EXISTS car (
    id TEXT PRIMARY KEY,
    uuid TEXT UNIQUE,
    username TEXT,
    email TEXT,
    manufacturer TEXT REFERENCES manufacturer DEFERRABLE INITIALLY DEFERRED,
) STRICT WITHOUT ROWID;
 */

/*
SELECT id, uuid, username FROM car
 */
