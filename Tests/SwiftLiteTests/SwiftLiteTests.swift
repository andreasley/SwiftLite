import Testing
import Foundation
@testable import SwiftLite

class SampleModels
{
    @Model class Car
    {
        //        @Attribute(.readOnly, .unique)
        let publicId: UUID = UUID()
        
        var name: String
        
        var year: Int
        
        var manufacturer: Manufacturer?
        
        init(name: String, year: Int)
        {
            self.name = name
            self.year = year
        }
    }
    
    @Model class Manufacturer
    {
    //    @Attribute(.readOnly, .unique)
        var publicId: UUID = UUID()
        
        var name: String
        
        init(name: String)
        {
            self.name = name
        }
    }
}

@Test func openDatabaseWithInvalidPath() async throws
{
    let url = URL(string: "notAFileUrl")!
    #expect(throws: Database.Error.notAFileUrl(url)) {
        try Database(storage: .file(url))
    }
}

@Test func openDatabaseInMemory() async throws
{
    let db = try Database(storage: .inMemory)
    
    let xc40 = SampleModels.Car(name: "XC40", year: 2023)
//    xc40.save(to: db)
//    db.insert(xc40)
//    db.save()
    
    try db.close()
}
