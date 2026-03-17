# Database Logging System - Granular Change Log

## Overview

The Database logging system has been updated to provide **granular, operation-level logging** that only captures **successful transactions**. This design is optimized for distributed sync scenarios where you need detailed, field-level tracking of what actually changed in the database.

## Key Changes

### 1. Only Successful Transactions Are Logged

❌ **Removed:**
- `transactionBegin` events
- `transactionCommit` events  
- `transactionRollback` events

✅ **Result:**
- Failed/rolled-back transactions leave **no trace** in the log
- Only changes that actually made it into the database are logged
- Cleaner log with no "noise" from failed operations

### 2. Granular Schema Logging

#### Table Creation
When a table is created, the following **separate** log entries are generated:

1. **Table Created** - One entry for the table itself
2. **Column Added** - One entry **per column** with storage class metadata
3. **Foreign Key Added** - One entry **per foreign key** with reference details
4. **Index Created** - One entry **per index** with columns and uniqueness

**Example:** Creating a `User` table with 5 columns, 2 foreign keys, and 1 index generates:
- 1 table_created entry
- 5 column_added entries
- 2 foreign_key_added entries
- 1 index_created entry
- **Total: 9 log entries**

#### Schema Updates
Each operation is logged separately:
- **Column Added** - Separate entry for each new column
- **Index Created** - Separate entry for each new index
- **Index Dropped** - Separate entry for each removed index

### 3. Granular Data Logging

#### Row Creation
When a row is created, the following **separate** log entries are generated:

1. **Row Created** - One entry marking the row creation (no field data)
2. **Field Updated** - One entry **per field** with the initial value

**Example:** Creating a `User` with name, email, age, and isActive generates:
- 1 row_created entry
- 4 field_updated entries (one for each field)
- **Total: 5 log entries**

#### Row Update
Each changed field gets its own log entry:
- **Field Updated** - One entry **per changed field** with new value

**Example:** Updating a user's name and email generates:
- 2 field_updated entries
- **Total: 2 log entries**

#### Row Deletion
- **Row Deleted** - One entry marking the deletion (no field data needed)

## Updated Operation Types

```swift
public enum OperationType: String, Sendable {
    // Schema operations
    case tableCreated = "table_created"
    case columnAdded = "column_added"
    case indexCreated = "index_created"
    case indexDropped = "index_dropped"
    case foreignKeyAdded = "foreign_key_added"
    
    // Data operations
    case rowCreated = "row_created"
    case rowDeleted = "row_deleted"
    case fieldUpdated = "field_updated"  // ← Changed from rowUpdated
}
```

## Log Entry Structure

Each entry still contains:
```swift
- id: UUID                    // Unique entry ID
- timestamp: Date             // When it occurred
- transactionId: UUID        // Groups related operations
- operationType: OperationType // What happened
- tableName: String?          // Which table
- objectId: UUID?             // Which object (for data changes)
- columnName: String?         // Which field (for field updates/additions)
- oldValue: String?           // Previous value (currently unused)
- newValue: String?           // New value (for field updates)
- metadata: String?           // JSON-encoded extras (for schema ops)
```

## Benefits of Granular Logging

### 1. **Field-Level Conflict Resolution**
```swift
// Detect conflicts at field level
let localChanges = entries.filter { 
    $0.operationType == .fieldUpdated && 
    $0.objectId == userId && 
    $0.columnName == "email" 
}

let remoteChanges = remoteEntries.filter { 
    $0.operationType == .fieldUpdated && 
    $0.objectId == userId && 
    $0.columnName == "email" 
}

// Only email changed, no conflict with name changes
```

### 2. **Partial Sync**
```swift
// Sync only specific fields
let nameSyncEntries = entries.filter { 
    $0.operationType == .fieldUpdated && 
    $0.columnName == "name" 
}
```

### 3. **Fine-Grained Schema Evolution**
```swift
// Track exactly which columns were added when
let addedColumns = entries.filter { 
    $0.operationType == .columnAdded &&
    $0.tableName == "User"
}
print("User table gained \(addedColumns.count) columns")
```

### 4. **Accurate Change Counting**
```swift
// Count actual field changes, not just row updates
let totalFieldChanges = entries.filter { 
    $0.operationType == .fieldUpdated 
}.count
```

## Examples

### Example 1: Creating a Car
```swift
// Code
let car = Car(db: db)
car.name = "Tesla Model 3"
car.price = 45000
car.year = 2024
try await db.save(changeset: car.changeset)

// Log entries generated:
// 1. row_created       table=Car, objectId=<uuid>
// 2. field_updated     table=Car, objectId=<uuid>, column=id, newValue=<uuid>
// 3. field_updated     table=Car, objectId=<uuid>, column=name, newValue="Tesla Model 3"
// 4. field_updated     table=Car, objectId=<uuid>, column=price, newValue="45000"
// 5. field_updated     table=Car, objectId=<uuid>, column=year, newValue="2024"
```

### Example 2: Updating Fields
```swift
// Code
car.name = "Tesla Model 3 Long Range"
car.price = 48000
try await db.save(changeset: car.changeset)

// Log entries generated:
// 1. field_updated     table=Car, objectId=<uuid>, column=name, newValue="Tesla Model 3 Long Range"
// 2. field_updated     table=Car, objectId=<uuid>, column=price, newValue="48000"
```

### Example 3: Schema Migration
```swift
// Code - Adding a 'color' column to Car table
try await db.register(models: Car.self) // Car now has a 'color' property

// Log entries generated:
// 1. column_added      table=Car, column=color, metadata={"storageClass":"text"}
```

### Example 4: Querying Field History
```swift
// Get all changes to a specific field
let priceHistory = try await db.getLogEntries(tableName: "Car")
    .filter { $0.objectId == carId && $0.columnName == "price" }
    .sorted { $0.timestamp < $1.timestamp }

for entry in priceHistory {
    print("[\(entry.timestamp)] Price changed to \(entry.newValue ?? "nil")")
}
```

## Distributed Sync Scenarios

### Scenario 1: Field-Level Last-Write-Wins
```swift
func syncField(local: LogEntry, remote: LogEntry) -> LogEntry {
    // Even if same object, different fields don't conflict
    if local.columnName != remote.columnName {
        return .noConflict
    }
    
    // Same field - use timestamp
    return local.timestamp > remote.timestamp ? local : remote
}
```

### Scenario 2: Reconstruct Object State
```swift
func reconstructObject(objectId: UUID, at timestamp: Date) async throws -> [String: String] {
    let entries = try await db.getLogEntries(to: timestamp)
        .filter { $0.objectId == objectId }
        .sorted { $0.timestamp < $1.timestamp }
    
    var state: [String: String] = [:]
    
    for entry in entries {
        if entry.operationType == .rowDeleted {
            return [:] // Object was deleted
        }
        
        if entry.operationType == .fieldUpdated,
           let column = entry.columnName,
           let value = entry.newValue {
            state[column] = value
        }
    }
    
    return state
}
```

### Scenario 3: Selective Sync
```swift
// Sync only non-sensitive fields
let publicFields = ["name", "year", "color"]
let syncEntries = try await db.getLogEntries(from: lastSync)
    .filter { entry in
        guard let column = entry.columnName else { return true }
        return publicFields.contains(column)
    }
```

## Performance Considerations

### Log Growth
- Creating a row with N fields: N+1 entries
- Updating M fields: M entries
- Creating table with C columns: C+1 entries (+ foreign keys + indexes)

**Example Database with 1000 users (10 fields each):**
- Initial creation: 1000 × 11 = 11,000 entries
- Updating 100 users (average 2 fields each): 200 entries
- Total: ~11,200 entries (~5-6 MB)

### Optimization Tips
1. **Batch Queries** - Fetch related entries together
2. **Index Usage** - Log table has indexes on timestamp, transactionId, tableName, objectId
3. **Archival** - Archive old field-level changes while keeping recent row-level events
4. **Compression** - Field values can be compressed for long-term storage

## Migration Notes

### From Previous Version
If you had the old logging system with transaction events:
1. The database will continue to work
2. Old logs won't have granular field data
3. New transactions will use the granular format
4. Consider regenerating logs if you need consistency

### Database Compatibility
- Log table schema is unchanged
- Only the `operation_type` values and logging pattern changed
- Existing logs remain valid but will have `row_updated` instead of `field_updated`

## Summary

The updated logging system provides:
- ✅ **Granular tracking** - Every field change is logged separately
- ✅ **Clean logs** - Only successful operations appear
- ✅ **Better sync** - Field-level conflict resolution
- ✅ **Detailed schema history** - Every column/index operation tracked
- ✅ **Flexible queries** - Filter by field, object, table, or time range

This granular approach makes the log ideal for sophisticated distributed sync solutions where you need precise control over what changed, when it changed, and how to merge concurrent modifications.
