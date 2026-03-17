import Foundation

// MARK: - Database Logging System for Distributed Sync
//
// This file demonstrates how to use the comprehensive logging system built into
// the Database class. All database operations are automatically logged to a separate
// SQLite file for use in distributed sync solutions.

// MARK: - Overview
//
// The logging system tracks:
// 1. Schema changes (table creation, column addition, index operations, foreign keys)
// 2. Data modifications (row creation, deletion, field updates)
// 3. Transaction lifecycle (begin, commit, rollback)
//
// Each log entry includes:
// - Unique ID
// - Timestamp (for temporal ordering)
// - Transaction ID (for grouping related operations)
// - Operation type
// - Affected table/object/column
// - Old and new values (for data changes)
// - Metadata (JSON-encoded additional information)

// MARK: - Basic Usage

func basicExample() async throws {
    // Create a database with logging enabled (default behavior)
    let dbURL = URL(fileURLWithPath: "/path/to/database.sqlite")
    let database = try await Database(storage: .file(dbURL), enableLogging: true)
    
    // The log file will be created at: /path/to/database.log.sqlite
    
    // All operations are automatically logged
    // No additional code needed for basic logging
    
    // Clean up
    try await database.close()
}

// MARK: - Accessing Log Entries

func queryLogExample() async throws {
    let dbURL = URL(fileURLWithPath: "/path/to/database.sqlite")
    let database = try await Database(storage: .file(dbURL))
    
    // Get all log entries from the last 24 hours
    let yesterday = Date().addingTimeInterval(-86400)
    let entries = try await database.getLogEntries(from: yesterday)
    
    for entry in entries {
        print("[\(entry.timestamp)] \(entry.operationType.rawValue)")
        if let tableName = entry.tableName {
            print("  Table: \(tableName)")
        }
        if let objectId = entry.objectId {
            print("  Object ID: \(objectId)")
        }
        if let columnName = entry.columnName {
            print("  Column: \(columnName)")
        }
        if let newValue = entry.newValue {
            print("  New Value: \(newValue)")
        }
    }
    
    try await database.close()
}

// MARK: - Filtering Log Entries

func filteredLogExample() async throws {
    let database = try await Database(storage: .file(URL(fileURLWithPath: "/path/to/db.sqlite")))
    
    // Get entries for a specific table
    let userTableEntries = try await database.getLogEntries(
        tableName: "User",
        limit: 100
    )
    
    // Get entries for a specific transaction
    let transactionId = UUID()
    let transactionEntries = try await database.getLogEntries(
        transactionId: transactionId
    )
    
    // Get entries in a date range
    let startDate = Date().addingTimeInterval(-3600) // 1 hour ago
    let endDate = Date()
    let recentEntries = try await database.getLogEntries(
        from: startDate,
        to: endDate
    )
    
    try await database.close()
}

// MARK: - Tracking Transactions

func transactionTrackingExample() async throws {
    let database = try await Database(storage: .file(URL(fileURLWithPath: "/path/to/db.sqlite")))
    
    // Get all transaction IDs from the last week
    let weekAgo = Date().addingTimeInterval(-604800)
    let transactionIds = try await database.getLogTransactions(from: weekAgo)
    
    print("Found \(transactionIds.count) transactions in the last week")
    
    // Fetch details for each transaction
    for transactionId in transactionIds {
        let entries = try await database.getLogEntries(transactionId: transactionId)
        
        // Check transaction type
        if let beginEntry = entries.first(where: { $0.operationType == .transactionBegin }) {
            print("Transaction \(transactionId): \(beginEntry.metadata ?? "unknown type")")
        }
        
        // Check if committed or rolled back
        let wasCommitted = entries.contains { $0.operationType == .transactionCommit }
        let wasRolledBack = entries.contains { $0.operationType == .transactionRollback }
        
        print("  Status: \(wasCommitted ? "✅ Committed" : wasRolledBack ? "❌ Rolled back" : "⚠️ Unknown")")
        print("  Operations: \(entries.count)")
    }
    
    try await database.close()
}

// MARK: - Analyzing Schema Changes

func schemaChangeExample() async throws {
    let database = try await Database(storage: .file(URL(fileURLWithPath: "/path/to/db.sqlite")))
    
    // Get all schema changes
    let allEntries = try await database.getLogEntries()
    let schemaChanges = allEntries.filter { entry in
        switch entry.operationType {
        case .tableCreated, .columnAdded, .indexCreated, .indexDropped, .foreignKeyAdded:
            return true
        default:
            return false
        }
    }
    
    print("Schema Changes:")
    for change in schemaChanges {
        print("  [\(change.timestamp)] \(change.operationType.rawValue)")
        if let tableName = change.tableName {
            print("    Table: \(tableName)")
        }
        if let columnName = change.columnName {
            print("    Column: \(columnName)")
        }
        if let metadata = change.metadata {
            print("    Metadata: \(metadata)")
        }
    }
    
    try await database.close()
}

// MARK: - Analyzing Data Changes

func dataChangeExample() async throws {
    let database = try await Database(storage: .file(URL(fileURLWithPath: "/path/to/db.sqlite")))
    
    // Get all data modifications for a specific object
    let objectId = UUID() // Replace with actual object ID
    let objectChanges = try await database.getLogEntries()
        .filter { $0.objectId == objectId }
    
    print("Changes for object \(objectId):")
    for change in objectChanges {
        print("  [\(change.timestamp)] \(change.operationType.rawValue)")
        if let columnName = change.columnName {
            print("    Field: \(columnName)")
            if let oldValue = change.oldValue {
                print("    Old Value: \(oldValue)")
            }
            if let newValue = change.newValue {
                print("    New Value: \(newValue)")
            }
        }
    }
    
    try await database.close()
}

// MARK: - Using the Logger Directly

func directLoggerExample() async throws {
    let database = try await Database(storage: .file(URL(fileURLWithPath: "/path/to/db.sqlite")))
    
    // Access the logger directly for advanced operations
    guard let logger = await database.getLogger() else {
        print("Logging is not enabled")
        return
    }
    
    // The logger provides more control and additional methods
    // Most common operations are available through the Database API though
    
    try await database.close()
}

// MARK: - Distributed Sync Implementation Pattern

/// Example pattern for implementing distributed sync using the log
class SyncEngine {
    let database: Database
    var lastSyncTimestamp: Date
    
    init(database: Database, lastSyncTimestamp: Date) {
        self.database = database
        self.lastSyncTimestamp = lastSyncTimestamp
    }
    
    /// Synchronize changes since last sync
    func sync() async throws {
        // 1. Get all changes since last sync
        let changes = try await database.getLogEntries(from: lastSyncTimestamp)
        
        // 2. Group by transaction for atomic sync
        let transactions = Dictionary(grouping: changes, by: { $0.transactionId })
        
        // 3. Only sync committed transactions
        for (transactionId, entries) in transactions {
            let wasCommitted = entries.contains { $0.operationType == .transactionCommit }
            guard wasCommitted else { continue }
            
            // Filter out transaction control entries
            let dataEntries = entries.filter { entry in
                switch entry.operationType {
                case .rowCreated, .rowDeleted, .rowUpdated:
                    return true
                default:
                    return false
                }
            }
            
            // 4. Send to sync service
            try await sendToSyncService(transactionId: transactionId, entries: dataEntries)
        }
        
        // 5. Update last sync timestamp
        lastSyncTimestamp = Date()
    }
    
    /// Apply changes received from sync service
    func applyRemoteChanges(_ entries: [DatabaseLogger.LogEntry]) async throws {
        // Group by transaction
        let transactions = Dictionary(grouping: entries, by: { $0.transactionId })
        
        for (transactionId, entries) in transactions {
            // Apply all changes in a single transaction
            // Implementation depends on your Models and data structure
            print("Applying remote transaction \(transactionId) with \(entries.count) changes")
        }
    }
    
    private func sendToSyncService(transactionId: UUID, entries: [DatabaseLogger.LogEntry]) async throws {
        // Implementation depends on your sync backend
        print("Syncing transaction \(transactionId) with \(entries.count) changes")
    }
}

// MARK: - Conflict Resolution Pattern

/// Example conflict resolution using log timestamps
struct ConflictResolver {
    enum ConflictResolution {
        case useLocal
        case useRemote
        case merge(mergedValue: String)
    }
    
    /// Resolve conflicts between local and remote changes
    func resolveConflict(
        localChange: DatabaseLogger.LogEntry,
        remoteChange: DatabaseLogger.LogEntry
    ) -> ConflictResolution {
        // Last-write-wins strategy
        if localChange.timestamp > remoteChange.timestamp {
            return .useLocal
        } else if remoteChange.timestamp > localChange.timestamp {
            return .useRemote
        } else {
            // Same timestamp - use transaction ID as tiebreaker
            if localChange.transactionId.uuidString > remoteChange.transactionId.uuidString {
                return .useLocal
            } else {
                return .useRemote
            }
        }
    }
    
    /// Detect conflicts for an object
    func detectConflicts(
        objectId: UUID,
        localChanges: [DatabaseLogger.LogEntry],
        remoteChanges: [DatabaseLogger.LogEntry]
    ) -> [(local: DatabaseLogger.LogEntry, remote: DatabaseLogger.LogEntry)] {
        var conflicts: [(DatabaseLogger.LogEntry, DatabaseLogger.LogEntry)] = []
        
        // Find changes to the same fields
        for localChange in localChanges where localChange.objectId == objectId {
            for remoteChange in remoteChanges where remoteChange.objectId == objectId {
                // Same field changed in both places
                if localChange.columnName == remoteChange.columnName {
                    conflicts.append((localChange, remoteChange))
                }
            }
        }
        
        return conflicts
    }
}

// MARK: - Disabling Logging

func disableLoggingExample() async throws {
    // Create a database without logging
    let database = try await Database(
        storage: .file(URL(fileURLWithPath: "/path/to/db.sqlite")),
        enableLogging: false
    )
    
    // No log file will be created
    // Useful for temporary databases or when logging is not needed
    
    try await database.close()
}

// MARK: - In-Memory Database

func inMemoryExample() async throws {
    // In-memory databases don't support logging
    let database = try await Database(storage: .inMemory)
    
    // Logging is automatically disabled for in-memory databases
    
    try await database.close()
}

// MARK: - Log File Location

func logFileLocationExample() {
    // For a database at: /Users/username/Documents/myapp.sqlite
    // The log file will be: /Users/username/Documents/myapp.log.sqlite
    
    let dbURL = URL(fileURLWithPath: "/Users/username/Documents/myapp.sqlite")
    let logURL = dbURL.deletingPathExtension()
        .appendingPathExtension("log")
        .appendingPathExtension("sqlite")
    
    print("Log file location: \(logURL.path)")
}

// MARK: - Performance Considerations

/*
 Performance Notes:
 
 1. Logging is asynchronous - it won't significantly impact transaction performance
 2. Log writes use try? to avoid failing transactions if logging fails
 3. The log database is separate from the main database
 4. Indexes on timestamp, transaction_id, and object_id enable fast queries
 5. For high-volume systems, consider:
    - Periodic log archival
    - Log rotation
    - Batch sync instead of real-time
 
 Log File Growth:
 - Each operation creates 1-2 log entries
 - Schema changes include metadata (JSON)
 - Data changes log each field separately for updates
 - Typical entry size: 200-500 bytes
 - Estimate: ~100KB per 1000 operations
 
 Archival Strategy:
 - Archive logs older than sync window (e.g., 30 days)
 - Move to cold storage or delete based on retention policy
 - Keep schema change history longer than data change history
 */
