import SwiftLite

struct Application
{
    var db: Database
    
    init(db: Database) async throws
    {
        self.db = try await Database(server: .init(host: "localhost", port: 5432, user: "postgres", password: "postgres"), encryption: .none)
    }
    
    func run() async throws
    {
        let volvo = try await db.first(Manufacturer.self, where: { $0.name == "Volvo" })
        
        let car = Car(name: "XC40", year: 2023, manufacturer: volvo)
        try await car.save()
    }
    
    func search(searchTextFromUser: String) async throws -> [Car]
    {
        let carsMatchingText = try await db.fullTextSearch(Car.specifiedFields)
        return carsMatchingText
    }
    
    struct CarListView: View
    {
        @Environment(\.swiftLiteStore) private var store
        @Query(Car.Resolved.self, where: { $0.manufacturer?.name.contains("Volvo") }) private var cars // read-only; all references resolved; automatically generated prepared statement for SQLite (including the joins for the references)
        
        var body: some View
        {
            List(cars) { car in
                NavigationLink {
                    CarDetailView(car: car.live())
                } label: {
                    Text("\(car.manufacturer?.name ?? "Unknown") \(car.name)")
                }
                Button("Edit") {
                    editCar(car)
                }
            }
            .task {
                let cars = try await store.objects(Car.self) // editable objects; unresolved refererences
                cars.database.write { // transaction
                    for car in cars { car in
                        car.year = car.year + 1
                    }
                }
            }
        }
        
        func editCar(_ car: Car.Resolved)
        {
            let editableCar = car.editable()
            editableCar.name = "Test"
            editableCar.save()
        }
    }
    
    struct CarDetailView: View
    {
        @Observable var car: Car.Live // which variant of `Car`?
        
        var body: some View
        {
            TextField(text: $car.name)
        }
    }
}

@Partial(Car.self) struct CarPreview
{
    var name
    var year
}

@Model class Manufacturer
{
    @Property(defaultValue: "New Manufacturer", indexed: true)
    var name: String
}

@Model class Car
{
    static let specifiedFields = FullTextIndex {
        self.name
        self.year
        self.manufacturer?.name
        self.engine?.name
    }
    
    @Property(defaultValue: "New Car")
    var name: String
    
    var year: Int
    
    var manufacturer: Manufacturer?
    
    @Property(storage: .inline) // store fields of nested object in same table
    var details: Details
    
    @Property(storage: .reference) // one-way reference
    var engine: Engine?
    
    @Property(storage: .relation, onDelete: .cascade) // two-way relation
    var owner: Owner?
    
    var image: SwiftLite.File?
    
    extension Car
    {
        class Details
        {
            var hasHood: Bool
        }
    }
    
    @Model class Engine
    {
        static var tableName = "motor"
        
        var name: String
        var cylinders: Int
    }
    
    @Model class Owner
    {
        static let allFields: FullTextIndex
        
        var firstName: String
        var lastName: String
    }
}
    
    
/// Macro-generated

extension Car
{
    class PreFetched
    {
        var name: String
        var year: Int
        var manufacturer: Manufacturer.Resolved?
        //etc.
    }
}
