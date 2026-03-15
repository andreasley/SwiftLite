import SwiftLite
import Foundation


let temporaryDirectory = URL.temporaryDirectory.appending(component: "SwiftLiteDevelopment", directoryHint: .isDirectory)
let fileUrl = temporaryDirectory.appending(component: "test.sqlite", directoryHint: .notDirectory)

try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)

let db = try Database(storage: .file(fileUrl))
try await db.register(models: Car.self)

var defaultEngine: Engine.Snapshot
if let firstEngine = try await db.get(Engine.Snapshot.self).first {
    defaultEngine = firstEngine
} else {
    let newEngine = Engine(db: db, name: "Blom")
    try await newEngine.save()
    guard let newEngineSnapshot = try await db.get(Engine.Snapshot.self, from: newEngine) else {
        fatalError("Failed to find Engine Snapshot for newly created Engine")
    }
    defaultEngine = newEngineSnapshot
}

let car = Car(db: db, name: "test", engine: defaultEngine)
try await car.save()

let cars = try await db.get(Car.self)

print(cars)
//try FileManager.default.removeItem(at: temporaryDirectory)
