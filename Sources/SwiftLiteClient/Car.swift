import SwiftLite
import Foundation

@Model class Car
{
    static let nameYearIndex = "nameYearIndex"
    
    @Indexed @Unique
    let publicId: UUID
    
    @Indexed(index: nameYearIndex)
    var name: String
    
    @Indexed(index: nameYearIndex) // @DefaultValue(2025)
    var year: Int
    
    var manufacturer: Manufacturer?

    var réböt: String

    convenience init(name: String, year: Int)
    {
        self.init(publicId: UUID(), name: name, year: year, réböt: "bla")
    }
}

class MacroExtendedCar
{
    let id: UUID
    
    let publicId: UUID
    
    var name: String = ""
    var year: Int = 0
    var manufacturer: Manufacturer?
    
    
    // MARK: generated
    
    static let tableName = "macro_extended_car"
    
    private static let entity = Schema.Entity<Car>(name: "Car", tableName: "car", properties: [
        .init(name: "id", columnName: "id", sqliteType: .text, isPrimaryKey: true, isUnique: false, isIndexed: false),
            .init(name: "publicId", columnName: "public_id", sqliteType: .integer, isPrimaryKey: false, isUnique: false, isIndexed: false),
            .init(name: "name", columnName: "name", sqliteType: .integer, isPrimaryKey: false, isUnique: false, isIndexed: false),
            .init(name: "year", columnName: "year", sqliteType: .integer, isPrimaryKey: false, isUnique: false, isIndexed: false),
            .init(name: "manufacturer", columnName: "manufacturer", sqliteType: .integer, isPrimaryKey: false, isUnique: false, isIndexed: false),
            .init(name: "réböt", columnName: "rue9buf6t", sqliteType: .integer, isPrimaryKey: false, isUnique: false, isIndexed: false)
        ])

    private static let __schemaRegistration: Void = {
        Schema.default.register(entity)
    }()
    
    init()
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
    
    static let createTableStatement: String =
    """
    CREATE TABLE IF NOT EXISTS car (
        id TEXT PRIMARY KEY,
        publicId TEXT UNIQUE,
        name TEXT,
        year INTEGER,
        manufacturer TEXT REFERENCES manufacturer DEFERRABLE INITIALLY DEFERRED,
    ) STRICT WITHOUT ROWID;
    """
    
    static let selectStatementFlat: String = "SELECT id, publicId, year, manufacturer FROM car"
    static let selectStatementFlatLimited: String = "SELECT id, publicId, year, manufacturer FROM car LIMIT ? OFFSET ?"
}

/*
 */
