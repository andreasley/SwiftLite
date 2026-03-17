import Foundation

// MARK: - Visual Comparison: Old vs New Logging Approach

/*
 
 ┌─────────────────────────────────────────────────────────────────────────┐
 │                    LOGGING SYSTEM COMPARISON                             │
 └─────────────────────────────────────────────────────────────────────────┘
 
 SCENARIO: Creating a User with 3 fields (name, email, age)
 
 ═══════════════════════════════════════════════════════════════════════════
 OLD APPROACH (Coarse-grained)
 ═══════════════════════════════════════════════════════════════════════════
 
 1. transaction_begin      txId=abc-123, metadata="write"
 2. row_created            txId=abc-123, table=User, objectId=user-001
                          metadata='{"name":"Alice","email":"alice@example.com","age":"30"}'
 3. transaction_commit     txId=abc-123
 
 Total: 3 entries
 
 PROBLEMS:
 ❌ Transaction noise (begin/commit entries)
 ❌ All fields bundled in metadata
 ❌ Can't query individual field changes
 ❌ Failed transactions still logged (with rollback)
 ❌ Field-level conflicts hard to detect
 
 ═══════════════════════════════════════════════════════════════════════════
 NEW APPROACH (Granular)
 ═══════════════════════════════════════════════════════════════════════════
 
 1. row_created            txId=abc-123, table=User, objectId=user-001
 2. field_updated          txId=abc-123, table=User, objectId=user-001, column=name, newValue="Alice"
 3. field_updated          txId=abc-123, table=User, objectId=user-001, column=email, newValue="alice@example.com"
 4. field_updated          txId=abc-123, table=User, objectId=user-001, column=age, newValue="30"
 
 Total: 4 entries (only if transaction succeeds!)
 
 BENEFITS:
 ✅ No transaction noise
 ✅ Each field is a separate entry
 ✅ Easy to query specific field changes
 ✅ Failed transactions invisible
 ✅ Field-level conflict resolution
 
 
 ═══════════════════════════════════════════════════════════════════════════
 SCENARIO: Updating 2 fields (email and age)
 ═══════════════════════════════════════════════════════════════════════════
 
 OLD APPROACH:
 ───────────────────────────────────────────────────────────────────────────
 1. transaction_begin      txId=def-456, metadata="write"
 2. row_updated            txId=def-456, table=User, objectId=user-001
                          metadata='{"email":"alice.smith@example.com","age":"31"}'
 3. transaction_commit     txId=def-456
 
 Total: 3 entries
 
 NEW APPROACH:
 ───────────────────────────────────────────────────────────────────────────
 1. field_updated          txId=def-456, table=User, objectId=user-001, column=email, newValue="alice.smith@example.com"
 2. field_updated          txId=def-456, table=User, objectId=user-001, column=age, newValue="31"
 
 Total: 2 entries
 
 
 ═══════════════════════════════════════════════════════════════════════════
 SCENARIO: Creating a table with 5 columns, 1 foreign key, 1 index
 ═══════════════════════════════════════════════════════════════════════════
 
 OLD APPROACH:
 ───────────────────────────────────────────────────────────────────────────
 1. transaction_begin      txId=ghi-789, metadata="schema_update"
 2. table_created          txId=ghi-789, table=Post
                          metadata='{"columns":[...5 columns...],"foreignKeys":[...]}'
 3. index_created          txId=ghi-789, table=Post
                          metadata='{"indexName":"idx_user_id",...}'
 4. foreign_key_added      txId=ghi-789, table=Post, column=user_id
                          metadata='{"referencedTable":"User",...}'
 5. transaction_commit     txId=ghi-789
 
 Total: 5 entries
 
 NEW APPROACH:
 ───────────────────────────────────────────────────────────────────────────
 1. table_created          txId=ghi-789, table=Post
 2. column_added           txId=ghi-789, table=Post, column=id, metadata='{"storageClass":"blob"}'
 3. column_added           txId=ghi-789, table=Post, column=title, metadata='{"storageClass":"text"}'
 4. column_added           txId=ghi-789, table=Post, column=content, metadata='{"storageClass":"text"}'
 5. column_added           txId=ghi-789, table=Post, column=user_id, metadata='{"storageClass":"blob"}'
 6. column_added           txId=ghi-789, table=Post, column=created_at, metadata='{"storageClass":"real"}'
 7. foreign_key_added      txId=ghi-789, table=Post, column=user_id, metadata='{"referencedTable":"User",...}'
 8. index_created          txId=ghi-789, table=Post, metadata='{"indexName":"idx_user_id",...}'
 
 Total: 8 entries
 
 
 ═══════════════════════════════════════════════════════════════════════════
 SCENARIO: Failed Transaction
 ═══════════════════════════════════════════════════════════════════════════
 
 Code:
   try await db.save(changeset: user.changeset) // Throws constraint violation
 
 OLD APPROACH:
 ───────────────────────────────────────────────────────────────────────────
 1. transaction_begin      txId=jkl-012, metadata="write"
 2. row_created            txId=jkl-012, table=User, objectId=user-002, metadata='...'
 3. transaction_rollback   txId=jkl-012
 
 Total: 3 entries (cluttering the log with failed operations)
 
 NEW APPROACH:
 ───────────────────────────────────────────────────────────────────────────
 (empty - nothing logged!)
 
 Total: 0 entries
 
 ═══════════════════════════════════════════════════════════════════════════
 
 */

// MARK: - Code Examples

func demonstrateGranularLogging() async throws {
    let db = try await Database(storage: .file(URL(fileURLWithPath: "/tmp/test.db")))
    guard let logger = await db.logger else {
        print("Failed to find logger")
        return
    }
    
    // QUERY 1: Get all changes to a specific field
    // ────────────────────────────────────────────
    let emailChanges = try await logger.getEntries()
        .filter { $0.operationType == .fieldUpdated && $0.columnName == "email" }
    
    print("Email was changed \(emailChanges.count) times")
    
    
    // QUERY 2: Detect field-level conflicts
    // ──────────────────────────────────────
    func hasConflict(local: DatabaseLogger.LogEntry, remote: DatabaseLogger.LogEntry) -> Bool {
        // Only conflicts if:
        // 1. Same object
        // 2. Same field
        // 3. Both are field updates
        return local.objectId == remote.objectId &&
               local.columnName == remote.columnName &&
               local.operationType == .fieldUpdated &&
               remote.operationType == .fieldUpdated
    }
    
    
    // QUERY 3: Reconstruct object at specific timestamp
    // ──────────────────────────────────────────────────
    func getObjectState(objectId: UUID, at timestamp: Date) async throws -> [String: String] {
        let entries = try await logger.getEntries(to: timestamp)
            .filter { $0.objectId == objectId }
            .sorted { $0.timestamp < $1.timestamp }
        
        var deleted = false
        var fields: [String: String] = [:]
        
        for entry in entries {
            switch entry.operationType {
            case .rowCreated:
                deleted = false
            case .rowDeleted:
                deleted = true
                fields.removeAll()
            case .fieldUpdated:
                if let column = entry.columnName, let value = entry.newValue {
                    fields[column] = value
                }
            default:
                break
            }
        }
        
        return deleted ? [:] : fields
    }
    
    
    // QUERY 4: Get field change history with timestamps
    // ──────────────────────────────────────────────────
    func getFieldHistory(objectId: UUID, field: String) async throws -> [(Date, String)] {
        let entries = try await logger.getEntries()
            .filter {
                $0.objectId == objectId && 
                $0.columnName == field &&
                $0.operationType == .fieldUpdated
            }
            .sorted { $0.timestamp < $1.timestamp }
        
        return entries.compactMap { entry in
            guard let value = entry.newValue else { return nil }
            return (entry.timestamp, value)
        }
    }
    
    let priceHistory = try await getFieldHistory(
        objectId: UUID(uuidString: "car-123")!,
        field: "price"
    )
    
    print("Price history:")
    for (date, price) in priceHistory {
        print("  \(date): $\(price)")
    }
    
    
    // QUERY 5: Count changes by field
    // ────────────────────────────────
    let fieldChangeCounts = try await logger.getEntries(from: Date().addingTimeInterval(-86400))
        .filter { $0.operationType == .fieldUpdated }
        .reduce(into: [String: Int]()) { counts, entry in
            if let column = entry.columnName {
                counts[column, default: 0] += 1
            }
        }
    
    print("Most changed fields in last 24 hours:")
    for (field, count) in fieldChangeCounts.sorted(by: { $0.value > $1.value }).prefix(5) {
        print("  \(field): \(count) changes")
    }
    
    
    // QUERY 6: Sync only specific fields
    // ───────────────────────────────────
    let lastSync = Date().addingTimeInterval(-3600) // 1 hour ago
    let syncableFields = ["name", "description", "price", "quantity"]
    
    let entriesToSync = try await logger.getEntries(from: lastSync)
        .filter { entry in
            // Include row creations/deletions
            if entry.operationType == .rowCreated || entry.operationType == .rowDeleted {
                return true
            }
            
            // For field updates, only include whitelisted fields
            if entry.operationType == .fieldUpdated,
               let column = entry.columnName {
                return syncableFields.contains(column)
            }
            
            return false
        }
    
    print("Syncing \(entriesToSync.count) entries")
    
    
    // QUERY 7: Detect schema evolution
    // ─────────────────────────────────
    let schemaChanges = try await logger.getEntries()
        .filter { entry in
            [.tableCreated, .columnAdded, .indexCreated, .indexDropped, .foreignKeyAdded]
                .contains(entry.operationType)
        }
        .sorted { $0.timestamp < $1.timestamp }
    
    print("\nSchema Evolution:")
    for change in schemaChanges {
        print("[\(change.timestamp)] \(change.operationType.rawValue) - \(change.tableName ?? "unknown")")
        if let column = change.columnName {
            print("  Column: \(column)")
        }
    }
    
    
    // QUERY 8: Merge concurrent field updates (last-write-wins per field)
    // ────────────────────────────────────────────────────────────────────
    func mergeChanges(local: [DatabaseLogger.LogEntry], remote: [DatabaseLogger.LogEntry]) -> [DatabaseLogger.LogEntry] {
        var merged: [String: DatabaseLogger.LogEntry] = [:] // field -> entry
        
        // Process all entries (local + remote)
        for entry in (local + remote) {
            guard entry.operationType == .fieldUpdated,
                  let column = entry.columnName else { continue }
            
            // Keep the one with the latest timestamp
            if let existing = merged[column] {
                if entry.timestamp > existing.timestamp {
                    merged[column] = entry
                }
            } else {
                merged[column] = entry
            }
        }
        
        return Array(merged.values)
    }
    
    try await db.close()
}

// MARK: - Performance Comparison

/*
 
 STORAGE EFFICIENCY
 ══════════════════
 
 Scenario: 1000 users with 10 fields each
 
 OLD APPROACH:
   Per user creation:
     - 1 transaction_begin    (~150 bytes)
     - 1 row_created          (~800 bytes with all fields in metadata)
     - 1 transaction_commit   (~150 bytes)
   Total: ~1.1 KB per user
   For 1000 users: ~1.1 MB
 
 NEW APPROACH:
   Per user creation:
     - 1 row_created          (~200 bytes)
     - 10 field_updated       (~250 bytes each)
   Total: ~2.7 KB per user
   For 1000 users: ~2.7 MB
 
 NOTE: New approach uses ~2.5x more space BUT provides much better queryability
 
 
 QUERY EFFICIENCY
 ════════════════
 
 Query: "Find all email changes in the last week"
 
 OLD APPROACH:
   1. Fetch all row_updated entries
   2. Parse JSON metadata for each
   3. Filter those containing email field
   Complexity: O(n) with JSON parsing overhead
 
 NEW APPROACH:
   1. Query: WHERE column_name = 'email' AND operation_type = 'field_updated'
   2. Database index does the filtering
   Complexity: O(log n) with index
 
 Speedup: 10-100x faster for field-specific queries
 
 
 SYNC EFFICIENCY
 ═══════════════
 
 Scenario: Sync only 'name' and 'email' fields, ignore others
 
 OLD APPROACH:
   1. Fetch all entries
   2. Parse metadata JSON
   3. Extract only name/email
   4. Discard rest
   Network waste: High
 
 NEW APPROACH:
   1. Query: WHERE column_name IN ('name', 'email')
   2. Get only relevant entries
   Network waste: None
 
 Bandwidth savings: 50-80% for selective sync
 
 */
