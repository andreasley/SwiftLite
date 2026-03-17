# Database Logging System for Distributed Sync

## Overview

A comprehensive logging system has been added to the `Database` class to track all database operations in preparation for a distributed sync solution. All modifications are logged to a separate SQLite database with timestamps and transaction IDs.

## What's New

### 1. DatabaseLogger Actor (`DatabaseLogger.swift`)
A new actor that manages a separate SQLite database for logging all operations.

**Key Features:**
- Separate log database (e.g., `mydb.log.sqlite`) alongside main database
- Thread-safe logging using Swift's actor model
- Comprehensive operation tracking with timestamps and transaction IDs
- Efficient querying with indexed columns (timestamp, transaction_id, table_name, object_id)
- Batch logging support for performance

**Logged Operations:**
- **Schema Changes:**
  - Table creation
  - Column addition
  - Index creation/deletion
  - Foreign key addition
  
- **Data Changes:**
  - Row creation (with all field values)
  - Row deletion
  - Row updates (individual field changes)
  
- **Transaction Lifecycle:**
  - Transaction begin (with type: read/write/schema_update)
  - Transaction commit
  - Transaction rollback

### 2. Database Class Integration
The `Database` class has been enhanced with automatic logging:

**New Properties:**
- `logger: DatabaseLogger?` - The logger instance
- `currentTransactionId: UUID?` - Tracks the current transaction

**New Initialization Parameter:**
```swift
init(storage: StorageType, cacheSizeLimit: CacheSize? = nil, enableLogging: Bool = true)
```

**New Methods:**
```swift
// Access the logger
func getLogger() -> DatabaseLogger?

// Query log entries
func getLogEntries(
    from startDate: Date? = nil,
    to endDate: Date? = nil,
    transactionId: UUID? = nil,
    tableName: String? = nil,
    limit: Int? = nil
) async throws -> [DatabaseLogger.LogEntry]

// Get transaction IDs
func getLogTransactions(
    from startDate: Date? = nil,
    to endDate: Date? = nil
) async throws -> [UUID]
```

### 3. Log Entry Structure
Each log entry contains:
- `id: UUID` - Unique entry identifier
- `timestamp: Date` - When the operation occurred
- `transactionId: UUID` - Groups related operations
- `operationType: OperationType` - Type of operation
- `tableName: String?` - Affected table
- `objectId: UUID?` - Affected object (for data changes)
- `columnName: String?` - Affected column
- `oldValue: String?` - Previous value (for updates)
- `newValue: String?` - New value
- `metadata: String?` - JSON-encoded additional information

### 4. Utility Classes
Two additional utility files provide helper functionality:

**`DatabaseLoggingExamples.swift`:**
- Complete usage examples
- Query patterns
- Conflict resolution examples
- Sync implementation patterns

**`DatabaseLogUtilities.swift`:**
- Statistics gathering
- Log archival
- JSON export/import
- Integrity verification
- Report generation

## Usage

### Basic Usage (Automatic)
```swift
// Create database with logging enabled (default)
let database = try Database(storage: .file(dbURL))

// All operations are automatically logged
try await database.register(models: User.self, Post.self)
// ... use database normally
```

### Querying Logs
```swift
// Get recent changes
let yesterday = Date().addingTimeInterval(-86400)
let entries = try await database.getLogEntries(from: yesterday)

// Get changes for specific table
let userChanges = try await database.getLogEntries(tableName: "User")

// Get changes in a transaction
let transactionEntries = try await database.getLogEntries(transactionId: someUUID)
```

### Maintenance
```swift
// Get statistics
let stats = try await DatabaseLogUtilities.getStatistics(
    logger: logger, 
    logFileURL: logURL
)
print("File size: \(stats.fileSizeMB) MB")

// Archive old entries
let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 3600)
try await DatabaseLogUtilities.archiveEntries(
    logger: logger,
    options: .init(
        olderThan: thirtyDaysAgo,
        deleteAfterArchive: true,
        archiveURL: archiveURL
    )
)

// Vacuum to reclaim space
try DatabaseLogUtilities.vacuum(logFileURL: logURL)
```

## Distributed Sync Pattern

The log enables various sync strategies:

### 1. Last-Write-Wins
```swift
// Compare timestamps to resolve conflicts
if localChange.timestamp > remoteChange.timestamp {
    // Use local version
} else {
    // Use remote version
}
```

### 2. Transaction-Based Sync
```swift
// Sync complete transactions atomically
let transactions = try await database.getLogTransactions(from: lastSync)
for transactionId in transactions {
    let entries = try await database.getLogEntries(transactionId: transactionId)
    // Send to sync service
}
```

### 3. Conflict Detection
```swift
// Find concurrent modifications
let localChanges = try await database.getLogEntries(from: lastSync)
let conflicts = detectConflicts(localChanges, remoteChanges)
```

## Performance Considerations

### Log Growth
- Typical entry size: 200-500 bytes
- Estimate: ~100KB per 1,000 operations
- Schema changes include more metadata

### Optimization Tips
1. **Archive Regularly**: Move old entries to archive database
2. **Vacuum Periodically**: Reclaim space after deletion
3. **Batch Sync**: Sync in batches rather than real-time for high-volume apps
4. **Index Usage**: Queries on indexed columns (timestamp, transaction_id) are fast
5. **Logging Failures**: Uses `try?` to avoid blocking transactions

### Log File Location
- Main database: `/path/to/database.sqlite`
- Log database: `/path/to/database.log.sqlite`

## Implementation Details

### Transaction Tracking
Each transaction gets a unique UUID that's logged with:
1. Begin entry (with transaction type)
2. All operations within transaction
3. Commit or rollback entry

### Schema Changes
Schema changes are logged with detailed metadata:
```swift
try logger.logSchemaChange(
    transactionId: transactionId,
    operationType: .tableCreated,
    tableName: "User",
    metadata: [
        "columns": [...]
    ]
)
```

### Data Changes
Data changes log each field individually for updates:
```swift
// For each updated field
try logger.logDataChange(
    transactionId: transactionId,
    change: changedObject
)
```

## Testing

### Verify Logging
```swift
let database = try Database(storage: .file(dbURL))
let logger = await database.getLogger()
assert(logger != nil, "Logging should be enabled")

// Perform operations
try await database.register(models: User.self)

// Check logs
let entries = try await database.getLogEntries()
assert(!entries.isEmpty, "Should have logged operations")
```

### Verify Integrity
```swift
let issues = try await DatabaseLogUtilities.verifyIntegrity(logger: logger)
assert(issues.isEmpty, "Log should be intact")
```

## Future Enhancements

Possible extensions for production use:

1. **Log Compaction**: Merge related entries to reduce size
2. **Selective Logging**: Option to log only specific tables
3. **Encryption**: Encrypt sensitive log data
4. **Remote Logging**: Stream logs directly to sync service
5. **Log Rotation**: Automatic rotation based on size/time
6. **Batch Deletion**: Add delete method to DatabaseLogger
7. **Query Builder**: Type-safe query interface for logs
8. **Sync Markers**: Track sync progress per device/server

## Files Modified/Created

### Modified
- `Database.swift` - Added logging integration

### Created
- `DatabaseLogger.swift` - Core logging implementation
- `DatabaseLoggingExamples.swift` - Usage examples
- `DatabaseLogUtilities.swift` - Maintenance utilities
- `README_LOGGING.md` - This file

## Migration Guide

### Existing Projects
1. Update to new `Database` initializer signature
2. Existing code continues to work with `enableLogging: true` by default
3. To disable logging: `Database(storage: .file(url), enableLogging: false)`

### In-Memory Databases
- In-memory databases automatically disable logging
- No changes needed for existing in-memory usage

## Conclusion

This logging system provides a complete audit trail of all database operations, making it suitable as a foundation for distributed sync solutions. All operations are tracked with timestamps and transaction IDs, enabling conflict resolution, incremental sync, and data recovery scenarios.
