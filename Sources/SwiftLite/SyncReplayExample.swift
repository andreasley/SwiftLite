import Foundation

/// Example demonstrating a practical log replay scenario for distributed sync
///
/// This shows how the improved roundtripping enables reliable sync between devices

struct SyncManager {
    let logger: DatabaseLogger
    
    /// Apply changes from a remote device's log to the local database
    func applyRemoteChanges(transactionId: UUID) async throws {
        print("🔄 Starting sync for transaction: \(transactionId)")
        
        // Retrieve all logged operations for this transaction
        let entries = try await logger.getEntries(transactionId: transactionId)
        
        print("   Found \(entries.count) log entries to replay")
        
        // Group entries by operation type for efficient processing
        let fieldUpdates = entries.filter { $0.operationType == .fieldUpdated }
        let rowCreations = entries.filter { $0.operationType == .rowCreated }
        let rowDeletions = entries.filter { $0.operationType == .rowDeleted }
        
        // 1. Apply row creations first
        for entry in rowCreations {
            guard let tableName = entry.tableName,
                  let objectId = entry.objectId else { continue }
            
            print("   ➕ Creating row in table '\(tableName)' with ID \(objectId)")
            // Execute INSERT statement...
        }
        
        // 2. Apply field updates
        for entry in fieldUpdates {
            guard let tableName = entry.tableName,
                  let objectId = entry.objectId,
                  let columnName = entry.columnName,
                  let newValue = entry.newValue else { continue }
            
            try await applyFieldUpdate(
                table: tableName,
                objectId: objectId,
                column: columnName,
                value: newValue
            )

        }
        
        // 3. Apply row deletions last
        for entry in rowDeletions {
            guard let tableName = entry.tableName,
                  let objectId = entry.objectId else { continue }
            
            print("   ➖ Deleting row from table '\(tableName)' with ID \(objectId)")
            // Execute DELETE statement...
        }
        
        print("✅ Sync complete for transaction: \(transactionId)")
    }
    
    /// Apply a single field update with type-safe value
    private func applyFieldUpdate(
        table: String,
        objectId: UUID,
        column: String,
        value: SQLValue
    ) async throws {
        print("   📝 Updating \(table).\(column) for object \(objectId)")
        
        // With the old system, you'd have to guess the type or have schema metadata
        // With the new system, the type is already known!
        
        switch value {
        case .string(let str):
            print("      Setting string value: \(str)")
            // Execute: UPDATE table SET column = ? WHERE id = ?
            // Bind as TEXT: str
            
        case .int(let int):
            print("      Setting int64 value: \(int)")
            // Execute: UPDATE table SET column = ? WHERE id = ?
            // Bind as INTEGER: int
            
        case .double(let double):
            print("      Setting double value: \(double)")
            // Execute: UPDATE table SET column = ? WHERE id = ?
            // Bind as REAL: double
            
        case .data(let data):
            print("      Setting data value: \(data.count) bytes")
            // Execute: UPDATE table SET column = ? WHERE id = ?
            // Bind as BLOB: data
            
        case .null:
            print("      Setting NULL")
            // Execute: UPDATE table SET column = NULL WHERE id = ?
        }
    }
}

/// Example showing conflict resolution using typed values
struct ConflictResolver {
    let logger: DatabaseLogger
    
    /// Resolve conflicts between local and remote changes
    func resolveConflict(
        localEntry: DatabaseLogger.LogEntry,
        remoteEntry: DatabaseLogger.LogEntry
    ) async -> DatabaseLogger.LogEntry? {
        
        guard let localValue = localEntry.newValue,
              let remoteValue = remoteEntry.newValue else {
            return nil
        }
                
        // Example: Use timestamp to decide winner
        let winner = localEntry.timestamp > remoteEntry.timestamp ? localEntry : remoteEntry
        
        print("🔧 Resolved conflict:")
        print("   Local:  \(localValue.debugDescription) at \(localEntry.timestamp)")
        print("   Remote: \(remoteValue.debugDescription) at \(remoteEntry.timestamp)")
        print("   Winner: \(winner == localEntry ? "local" : "remote")")
        
        return winner
    }
    
    /// Merge numeric values (example: collaborative counters)
    func mergeNumericValues(
        localEntry: DatabaseLogger.LogEntry,
        remoteEntry: DatabaseLogger.LogEntry
    ) async -> SQLValue? {
        
        guard let localValue = localEntry.newValue,
              let remoteValue = remoteEntry.newValue else {
            return nil
        }
        
        // Only works if both are numeric types
        switch (localValue, remoteValue) {
        case (.int(let localInt), .int(let remoteInt)):
            // Example: Sum both values (operational transform)
            let merged = localInt + remoteInt
            print("🔀 Merged int values: \(localInt) + \(remoteInt) = \(merged)")
            return .int(merged)
            
        case (.double(let localDouble), .double(let remoteDouble)):
            let merged = localDouble + remoteDouble
            print("🔀 Merged double values: \(localDouble) + \(remoteDouble) = \(merged)")
            return .double(merged)
            
        default:
            print("⚠️ Cannot merge non-numeric values")
            return nil
        }
    }
}

/// Example showing audit trail generation
struct AuditTrailGenerator {
    let logger: DatabaseLogger
    
    /// Generate human-readable audit trail from logs
    func generateAuditReport(transactionId: UUID) async throws -> String {
        let entries = try await logger.getEntries(transactionId: transactionId)
        
        var report = """
        ═══════════════════════════════════════════════════
        AUDIT REPORT
        Transaction ID: \(transactionId)
        Entries: \(entries.count)
        ═══════════════════════════════════════════════════
        
        """
        
        for (index, entry) in entries.enumerated() {
            report += "\n[\(index + 1)] \(entry.timestamp.formatted())\n"
            report += "    Operation: \(entry.operationType.rawValue)\n"
            
            if let tableName = entry.tableName {
                report += "    Table: \(tableName)\n"
            }
            
            if let objectId = entry.objectId {
                report += "    Object ID: \(objectId)\n"
            }
            
            if let columnName = entry.columnName,
               let newValue = entry.newValue {
                report += "    Column: \(columnName)\n"
                report += "    New Value: \(formatValueForAudit(newValue))\n"
            }
            
            report += "    ───────────────────────────────────────\n"
        }
        
        return report
    }
    
    private func formatValueForAudit(_ value: SQLValue) -> String {
        switch value {
        case .string(let str):
            return "\"\(str)\" (String)"
        case .int(let int):
            return "\(int) (Int64)"
        case .double(let double):
            return "\(double) (Double)"
        case .data(let data):
            return "<\(data.count) bytes of binary data>"
        case .null:
            return "NULL"
        }
    }
}

// MARK: - Example Usage

func demonstrateSync() async throws {
    let logURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("sync_example.sqlite")
    
    defer {
        try? FileManager.default.removeItem(at: logURL)
    }
    
    let logger = try await DatabaseLogger(logFileURL: logURL)
    
    // Simulate logging some changes
    let txId = UUID()
    
    try await logger.log(DatabaseLogger.LogEntry(
        transactionId: txId,
        operationType: .rowCreated,
        tableName: "users",
        objectId: UUID()
    ))
    
    let userId = UUID()
    
    try await logger.log(DatabaseLogger.LogEntry(
        transactionId: txId,
        operationType: .fieldUpdated,
        tableName: "users",
        objectId: userId,
        columnName: "age",
        newValue: .int(25)
    ))
    
    try await logger.log(DatabaseLogger.LogEntry(
        transactionId: txId,
        operationType: .fieldUpdated,
        tableName: "users",
        objectId: userId,
        columnName: "name",
        newValue: .string("Alice")
    ))
    
    // Apply sync
    let syncManager = SyncManager(logger: logger)
    try await syncManager.applyRemoteChanges(transactionId: txId)
    
    // Generate audit report
    let auditGenerator = AuditTrailGenerator(logger: logger)
    let report = try await auditGenerator.generateAuditReport(transactionId: txId)
    print("\n" + report)
    
    try await logger.close()
}

// Uncomment to run:
// Task {
//     try await demonstrateSync()
// }
