import Testing
import Foundation
@testable import SwiftLite

class SampleModels
{
    @Model class Car
    {
        // @Unique
        let publicId: UUID
        var name: String
        var year: Int
        var manufacturer: Manufacturer?
        
        convenience init(name: String, year: Int)
        {
            self.init(publicId: UUID(), name: name, year: year)
        }
    }
    
    @Model class Manufacturer
    {
        // @Unique
        let publicId: UUID
        var name: String
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
