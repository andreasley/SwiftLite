import SwiftLite
import Foundation

@Model class Car
{
    //    static let nameYearIndex: IndexGroup
    
    //    @Indexed @ReadOnly @Unique
    let publicId: UUID
    
    //    @Indexed(index: nameYearIndex)
    var name: String 
    
    //    @Indexed(index: nameYearIndex) @DefaultValue(2025)
    var year: Int
    
    var manufacturer: Manufacturer?
    
    convenience init(name: String)
    {
        self.init(name: name, year: 2025)
        self.name = name
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
    
    
    // MARK: generated

    private static let entity = Schema.Entity(properties: [
        Schema.Entity.Property(name: "publicId", type: "UUID", isPrimaryKey: false, isUnique: true, isIndexed: false),
        Schema.Entity.Property(name: "name", type: "String", isPrimaryKey: false, isUnique: false, isIndexed: false),
        Schema.Entity.Property(name: "year", type: "Int", isPrimaryKey: false, isUnique: false, isIndexed: false),
    ])
    
    private static let __schemaRegistration: Void = {
        Schema.default.register(entity)
    }()
    
    required init()
    {
        // for manual creation of new objects
        id = UUID()
        publicId = UUID()
    }
    
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
