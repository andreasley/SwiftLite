import SwiftLite
import Foundation
import Testing

@Suite("DatabaseLogger Value Roundtripping")
struct DatabaseLoggerRoundtripTests {
    
    @Test("String values can be roundtripped")
    func testStringRoundtrip() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        let logger = try await DatabaseLogger(logFileURL: tempURL)
        let transactionId = UUID()
        
        let originalValue = SQLValue.string("Hello, World!")
        
        // Log the value
        try await logger.log(DatabaseLogger.LogEntry(
            transactionId: transactionId,
            operationType: .fieldUpdated,
            tableName: "test",
            objectId: UUID(),
            columnName: "field",
            newValue: originalValue
        ))
        
        // Retrieve and verify
        let entries = try await logger.getEntries(transactionId: transactionId)
        let decoded = entries.first?.newValue
        
        #expect(decoded == originalValue, "String value should roundtrip correctly")
        
        try await logger.close()
    }
    
    @Test("Int64 values can be roundtripped")
    func testInt64Roundtrip() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        let logger = try await DatabaseLogger(logFileURL: tempURL)
        let transactionId = UUID()
        
        let originalValue = SQLValue.int(9223372036854775807) // Max Int64
        
        try await logger.log(DatabaseLogger.LogEntry(
            transactionId: transactionId,
            operationType: .fieldUpdated,
            tableName: "test",
            objectId: UUID(),
            columnName: "field",
            newValue: originalValue
        ))
        
        let entries = try await logger.getEntries(transactionId: transactionId)
        let decoded = entries.first?.newValue
        
        #expect(decoded == originalValue, "Int64 value should roundtrip correctly")
        
        try await logger.close()
    }
    
    @Test("Double values can be roundtripped")
    func testDoubleRoundtrip() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        let logger = try await DatabaseLogger(logFileURL: tempURL)
        let transactionId = UUID()
        
        let originalValue = SQLValue.double(3.14159265358979)
        
        try await logger.log(DatabaseLogger.LogEntry(
            transactionId: transactionId,
            operationType: .fieldUpdated,
            tableName: "test",
            objectId: UUID(),
            columnName: "field",
            newValue: originalValue
        ))
        
        let entries = try await logger.getEntries(transactionId: transactionId)
        let decoded = entries.first?.newValue
        
        #expect(decoded == originalValue, "Double value should roundtrip correctly")
        
        try await logger.close()
    }
    
    @Test("Data values can be roundtripped")
    func testDataRoundtrip() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        let logger = try await DatabaseLogger(logFileURL: tempURL)
        let transactionId = UUID()
        
        let testData = "Test Data".data(using: .utf8)!
        let originalValue = SQLValue.data(testData)
        
        try await logger.log(DatabaseLogger.LogEntry(
            transactionId: transactionId,
            operationType: .fieldUpdated,
            tableName: "test",
            objectId: UUID(),
            columnName: "field",
            newValue: originalValue
        ))
        
        let entries = try await logger.getEntries(transactionId: transactionId)
        let decoded = entries.first?.newValue
        
        #expect(decoded == originalValue, "Data value should roundtrip correctly")
        
        try await logger.close()
    }
    
    @Test("Null values can be roundtripped")
    func testNullRoundtrip() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        let logger = try await DatabaseLogger(logFileURL: tempURL)
        let transactionId = UUID()
        
        let originalValue = SQLValue.null
        
        try await logger.log(DatabaseLogger.LogEntry(
            transactionId: transactionId,
            operationType: .fieldUpdated,
            tableName: "test",
            objectId: UUID(),
            columnName: "field",
            newValue: originalValue
        ))
        
        let entries = try await logger.getEntries(transactionId: transactionId)
        let decoded = entries.first?.newValue
        
        #expect(decoded == originalValue, "Null value should roundtrip correctly")
        
        try await logger.close()
    }
    
    @Test("Logged values can be retrieved and decoded")
    func testEndToEndRoundtrip() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        let logger = try await DatabaseLogger(logFileURL: tempURL)
        let transactionId = UUID()
        
        // Log various types of values
        let testValues: [(String, SQLValue)] = [
            ("stringField", .string("test")),
            ("intField", .int(42)),
            ("doubleField", .double(3.14)),
            ("dataField", .data("binary".data(using: .utf8)!)),
            ("nullField", .null)
        ]
        
        for (fieldName, value) in testValues {
            try await logger.log(DatabaseLogger.LogEntry(
                transactionId: transactionId,
                operationType: .fieldUpdated,
                tableName: "test_table",
                objectId: UUID(),
                columnName: fieldName,
                newValue: value
            ))
        }
        
        // Retrieve and verify
        let entries = try await logger.getEntries(transactionId: transactionId)
        
        #expect(entries.count == testValues.count, "Should have logged all values")
        
        for (entry, (_, originalValue)) in zip(entries, testValues) {
            #expect(entry.newValue == originalValue, "Logged value should match original after roundtrip")
        }
        
        try await logger.close()
    }
}
