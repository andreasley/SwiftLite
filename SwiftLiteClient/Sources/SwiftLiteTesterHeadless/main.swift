import SwiftLite
import SwiftLiteTestModels
import Foundation

let temporaryDirectory = URL.temporaryDirectory.appending(component: "SwiftLiteDevelopment", directoryHint: .isDirectory)
let fileUrl = temporaryDirectory.appending(component: "test.sqlite", directoryHint: .notDirectory)

try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)

let db = try await Database(storage: .file(fileUrl))
try await db.register(models: Car.self)

let defaultEngine: Engine.Snapshot
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

let car = Car(db: db, color: .red, name: "test", engine: defaultEngine)
try await car.save()

for _ in 0..<100 {
    let car = Car(db: db, color: .blue, name: "test", engine: defaultEngine)
    try await car.save()
}


try await withThrowingTaskGroup(of: Void.self) { group in
    for _ in 0..<10 {
        group.addTask {
            for _ in 0..<10 {
                let car = Car(db: db, color: .silver, name: "test", engine: defaultEngine)
                try await car.save()
            }
        }
    }
    
    try await group.waitForAll()
}


let carCount = try await db.count(Car.self)
print(carCount)
//try FileManager.default.removeItem(at: temporaryDirectory)

let cars = try await db.get(Car.self)
print(cars.count)
