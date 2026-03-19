import SwiftUI
import SwiftLite
import SwiftLiteTestModels

@MainActor
protocol Creatable: ModelSnapshot
{
    static func create(database: Database, defaultEngine: Engine.Snapshot) -> Model
}

@MainActor
extension Car.Snapshot: Creatable
{
    static func create(database: Database, defaultEngine: Engine.Snapshot) -> Car
    {
        Car(db: database, engine: defaultEngine)
    }
}

@MainActor
extension Engine.Snapshot: Creatable
{
    static func create(database: Database, defaultEngine: Engine.Snapshot) -> Engine
    {
        Engine(db: database)
    }
}
