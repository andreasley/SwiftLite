import SwiftLite
import Foundation

@Model final class Car
{
    static let nameYearIndex = "nameYearIndex"
    
    @Indexed @Unique @DefaultValue(UUID())
    let publicId: UUID
    
    @Indexed(index: nameYearIndex)
    var name: String
    
    @Indexed(index: nameYearIndex)
    var year: Int
    
    var manufacturer: Manufacturer?

    var röt: String?
    
    @DefaultValue(0.1)
    var 😗: Decimal

    convenience init(name: String)
    {
        self.init(name: name, year: 2025)
    }
}

class MacroExtendedCar: InitializableFromResultRow
{
    let id: UUID
    
    let publicId: UUID
    
    var name: String = ""
    var year: Int = 0
    var manufacturer: Manufacturer?
    
    // MARK: generated
    
    static let tableName = "macro_extended_car"
    
    static let table = Schema.Table(name: "Car", columns: [
        .init(name: "id", type: UUID.self, isPrimaryKey: true, isNullable: false),
            .init(name: "publicId", type: UUID.self, isPrimaryKey: false, isNullable: false),
            .init(name: "name", type: String.self, isPrimaryKey: false, isNullable: false),
            .init(name: "year", type: Int.self, isPrimaryKey: false, isNullable: false),
            .init(name: "manufacturer", type: Manufacturer.self, isPrimaryKey: false, isNullable: true)
    ], indexes: [
        .init(name: "idx_publicId", isUnique: true, columns: ["publicId"])
    ])

//    private static let __schemaRegistration: Void = {
//        Schema.default.register(entity)
//    }()
    
    init()
    {
        // for manual creation of new objects
        id = UUID()
        publicId = UUID()
    }
    
    required init(row: SQLiteQueryResult) throws
    {
        self.id = try row.get(0)
        self.publicId = try row.get(1)
        self.name = try row.get(2)
        self.year = try row.get(3)
    }
    
    static let selectStatementFlat: String = "SELECT id, publicId, year, manufacturer FROM car"
    static let selectStatementFlatLimited: String = "SELECT id, publicId, year, manufacturer FROM car LIMIT ? OFFSET ?"
}

/*
 */
