import SwiftLite
import Foundation

@Model class Car
{
//    @Attribute(.readOnly, .unique)
    var publicId: UUID = UUID()
    
    var name: String
    
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
    var id: Int64 { 0 } // rowid
        var publicId: UUID { .init() } // stored
    var name: String = "" // stored
    var year: Int = 0 // stored
    var manufacturer: Manufacturer?
}

/*
CREATE TABLE car (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    uuid TEXT UNIQUE,
    username TEXT,
    email TEXT
);
 */

/*
SELECT id, uuid, username FROM car
 */
