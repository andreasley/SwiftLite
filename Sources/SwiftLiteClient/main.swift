import SwiftLite
import Foundation


let temporaryDirectory = URL.temporaryDirectory.appending(component: "SwiftLiteDevelopment", directoryHint: .isDirectory)
let fileUrl = temporaryDirectory.appending(component: "test.sqlite", directoryHint: .notDirectory)

try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)

let db = try Database(storage: .file(fileUrl))
db.register(models: Car.self)
let car = Car(name: "test")

//try FileManager.default.removeItem(at: temporaryDirectory)
