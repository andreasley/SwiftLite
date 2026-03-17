import Foundation

/// Example demonstrating the improved DatabaseLogger API with SQLValue
///
/// With `LogEntry.newValue` now being `SQLValue?` instead of `String?`,
/// the API is much cleaner and type-safe. No manual encoding/decoding needed!

func exampleSimplifiedUsage() async throws {
    let logURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("example_log.sqlite")
    
    defer {
        try? FileManager.default.removeItem(at: logURL)
    }
    
    let logger = try await DatabaseLogger(logFileURL: logURL)
    let transactionId = UUID()
    
    // Example 1: Log different types directly
    print("=== Example 1: Logging Different Types ===")
    
    // Log an Int64
    try await logger.log(DatabaseLogger.LogEntry(
        transactionId: transactionId,
        operationType: .fieldUpdated,
        tableName: "users",
        objectId: UUID(),
        columnName: "age",
        newValue: .int(42)  // ✅ Direct SQLValue!
    ))
    
    // Log a String
    try await logger.log(DatabaseLogger.LogEntry(
        transactionId: transactionId,
        operationType: .fieldUpdated,
        tableName: "users",
        objectId: UUID(),
        columnName: "name",
        newValue: .string("Alice")  // ✅ Direct SQLValue!
    ))
    
    // Log a Double
    try await logger.log(DatabaseLogger.LogEntry(
        transactionId: transactionId,
        operationType: .fieldUpdated,
        tableName: "users",
        objectId: UUID(),
        columnName: "rating",
        newValue: .double(4.5)  // ✅ Direct SQLValue!
    ))
    
    // Log Data
    let imageData = "fake image".data(using: .utf8)!
    try await logger.log(DatabaseLogger.LogEntry(
        transactionId: transactionId,
        operationType: .fieldUpdated,
        tableName: "users",
        objectId: UUID(),
        columnName: "avatar",
        newValue: .data(imageData)  // ✅ Direct SQLValue!
    ))
    
    print("✅ Logged 4 field updates")
    print()
    
    // Example 2: Retrieve and use values directly
    print("=== Example 2: Reading Back Values ===")
    let entries = try await logger.getEntries(transactionId: transactionId)
    
    for entry in entries {
        guard let value = entry.newValue else { continue }
        
        print("Column: \(entry.columnName ?? "unknown")")
        print("  Type-safe value: ", terminator: "")
        
        // ✅ Pattern match directly on SQLValue
        switch value {
        case .int(let int):
            print("Int64(\(int))")
        case .string(let str):
            print("String(\"\(str)\")")
        case .double(let double):
            print("Double(\(double))")
        case .data(let data):
            print("Data(\(data.count) bytes)")
        case .null:
            print("NULL")
        }
    }
    
    print()
    
    // Example 3: Replay scenario with type-safe values
    print("=== Example 3: Type-Safe Replay ===")
    
    for entry in entries {
        guard let columnName = entry.columnName,
              let value = entry.newValue else { continue }
        
        // Apply the value with full type information
        applyFieldUpdate(
            table: entry.tableName ?? "unknown",
            column: columnName,
            value: value  // ✅ No conversion needed!
        )
    }
    
    try await logger.close()
}

/// Apply a field update using type-safe SQLValue
func applyFieldUpdate(table: String, column: String, value: SQLValue) {
    print("UPDATE \(table) SET \(column) = ", terminator: "")
    
    switch value {
    case .string(let str):
        print("'\(str)' (TEXT)")
    case .int(let int):
        print("\(int) (INTEGER)")
    case .double(let double):
        print("\(double) (REAL)")
    case .data(let data):
        print("<\(data.count) bytes> (BLOB)")
    case .null:
        print("NULL")
    }
}

/// Example showing comparison with old API
func beforeAndAfterComparison() async throws {
    print("\n=== Before vs After Comparison ===\n")
    
    let logURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("comparison.sqlite")
    
    defer {
        try? FileManager.default.removeItem(at: logURL)
    }
    
    let logger = try await DatabaseLogger(logFileURL: logURL)
    let txId = UUID()
    
    print("OLD API (String-based):")
    print("""
    ❌ let encoded = sqlValueToString(.int(42))  // Returns "{\"int\":42}"
    ❌ try await logger.log(LogEntry(..., newValue: encoded))
    ❌ let entry = try await logger.getEntries(...).first
    ❌ let decoded = await logger.stringToSQLValue(entry.newValue!)
    ❌ // Now finally have SQLValue back!
    """)
    
    print("\nNEW API (SQLValue-based):")
    print("""
    ✅ try await logger.log(LogEntry(..., newValue: .int(42)))
    ✅ let entry = try await logger.getEntries(...).first
    ✅ let value = entry.newValue  // Already SQLValue!
    """)
    
    print("\nDemonstration:")
    
    // Log with new API
    try await logger.log(DatabaseLogger.LogEntry(
        transactionId: txId,
        operationType: .fieldUpdated,
        tableName: "test",
        objectId: UUID(),
        columnName: "count",
        newValue: .int(9223372036854775807)  // Max Int64
    ))
    
    // Retrieve with new API
    let entries = try await logger.getEntries(transactionId: txId)
    if let value = entries.first?.newValue {
        print("Retrieved value: \(value)")
        print("  Type: \(type(of: value))")
        if case .int(let intValue) = value {
            print("  Integer value: \(intValue)")
            print("  ✅ Perfect roundtrip!")
        }
    }
    
    try await logger.close()
}

/// Example showing advanced use cases
func advancedUseCases() async throws {
    print("\n=== Advanced Use Cases ===\n")
    
    let logURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("advanced.sqlite")
    
    defer {
        try? FileManager.default.removeItem(at: logURL)
    }
    
    let logger = try await DatabaseLogger(logFileURL: logURL)
    let txId = UUID()
    
    // Use case 1: Value transformation during replay
    print("1. Value Transformation:")
    
    try await logger.log(DatabaseLogger.LogEntry(
        transactionId: txId,
        operationType: .fieldUpdated,
        tableName: "settings",
        objectId: UUID(),
        columnName: "theme",
        newValue: .string("dark")
    ))
    
    let entries = try await logger.getEntries(transactionId: txId)
    if let entry = entries.first,
       case .string(let theme) = entry.newValue {
        let transformed = theme == "dark" ? "light" : "dark"
        print("  Original: \(theme)")
        print("  Transformed: \(transformed)")
    }
    
    print()
    
    // Use case 2: Value validation
    print("2. Value Validation:")
    
    try await logger.log(DatabaseLogger.LogEntry(
        transactionId: UUID(),
        operationType: .fieldUpdated,
        tableName: "products",
        objectId: UUID(),
        columnName: "price",
        newValue: .double(29.99)
    ))
    
    let allEntries = try await logger.getEntries()
    for entry in allEntries where entry.columnName == "price" {
        if case .double(let price) = entry.newValue {
            if price < 0 {
                print("  ⚠️ Invalid price: \(price)")
            } else {
                print("  ✅ Valid price: $\(price)")
            }
        }
    }
    
    print()
    
    // Use case 3: Conditional sync based on value type
    print("3. Conditional Sync:")
    
    let syncEntries = [
        DatabaseLogger.LogEntry(
            transactionId: UUID(),
            operationType: .fieldUpdated,
            tableName: "docs",
            objectId: UUID(),
            columnName: "content",
            newValue: .string("This is a large document...")
        ),
        DatabaseLogger.LogEntry(
            transactionId: UUID(),
            operationType: .fieldUpdated,
            tableName: "docs",
            objectId: UUID(),
            columnName: "wordCount",
            newValue: .int(1000)
        ),
    ]
    
    for entry in syncEntries {
        try await logger.log(entry)
        
        if let value = entry.newValue {
            switch value {
            case .string(let str) where str.count > 100:
                print("  📦 Large string - use delta sync")
            case .data(let data) where data.count > 1024:
                print("  📦 Large data - use chunked transfer")
            default:
                print("  📤 Small value - direct sync")
            }
        }
    }
    
    try await logger.close()
}

// Uncomment to run:
// Task {
//     try await exampleSimplifiedUsage()
//     try await beforeAndAfterComparison()
//     try await advancedUseCases()
// }
