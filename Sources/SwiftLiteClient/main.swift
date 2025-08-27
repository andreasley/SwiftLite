import SwiftLite

let a = 17
let b = 25

let (result, code) = #stringify(a + b)

print("The value \(result) was produced by the code \"\(code)\"")

let db = try Database(storage: .inMemory)
db.register(models: Car.self)
let car = Car(name: "test")
