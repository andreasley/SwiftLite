import Foundation

// MARK: - Quick Reference: Database Logging API

/*
 
 ┌─────────────────────────────────────────────────────────────────────────┐
 │                   DATABASE LOGGING QUICK REFERENCE                      │
 └─────────────────────────────────────────────────────────────────────────┘
 
 INITIALIZATION
 ──────────────
 
 ✓ With logging (default):
   let db = try Database(storage: .file(url))
 
 ✓ Without logging:
   let db = try Database(storage: .file(url), enableLogging: false)
 
 ✓ In-memory (no logging):
   let db = try Database(storage: .inMemory)
 
 
 QUERYING LOGS
 ─────────────
 
 ✓ Get all recent entries:
   let entries = try await db.getLogEntries(from: yesterday)
 
 ✓ Get entries for a table:
   let entries = try await db.getLogEntries(tableName: "User")
 
 ✓ Get entries for a transaction:
   let entries = try await db.getLogEntries(transactionId: uuid)
 
 ✓ Get entries in date range:
   let entries = try await db.getLogEntries(from: start, to: end)
 
 ✓ Get with limit:
   let entries = try await db.getLogEntries(limit: 100)
 
 ✓ Get transaction IDs:
   let txIds = try await db.getLogTransactions(from: yesterday)
 
 
 LOG ENTRY STRUCTURE
 ───────────────────
 
 struct LogEntry {
     let id: UUID                      // Entry unique ID
     let timestamp: Date                // When it happened
     let transactionId: UUID           // Group related ops
     let operationType: OperationType  // What happened
     let tableName: String?             // Which table
     let objectId: UUID?                // Which object
     let columnName: String?            // Which field
     let oldValue: String?              // Previous value
     let newValue: String?              // New value
     let metadata: String?              // JSON extras
 }
 
 
 OPERATION TYPES
 ───────────────
 
 Schema:                  Data:                Transaction:
   • table_created          • row_created         • transaction_begin
   • column_added           • row_deleted         • transaction_commit
   • index_created          • row_updated         • transaction_rollback
   • index_dropped
   • foreign_key_added
 
 
 MAINTENANCE
 ───────────
 
 ✓ Get statistics:
   let stats = try await DatabaseLogUtilities.getStatistics(
       logger: logger,
       logFileURL: logURL
   )
 
 ✓ Archive old entries:
   try await DatabaseLogUtilities.archiveEntries(
       logger: logger,
       options: .init(
           olderThan: thirtyDaysAgo,
           deleteAfterArchive: true,
           archiveURL: archiveURL
       )
   )
 
 ✓ Vacuum database:
   try DatabaseLogUtilities.vacuum(logFileURL: logURL)
 
 ✓ Verify integrity:
   let issues = try await DatabaseLogUtilities.verifyIntegrity(logger: logger)
 
 ✓ Generate report:
   let report = try await DatabaseLogUtilities.generateReport(
       logger: logger,
       from: startDate,
       to: endDate
   )
 
 
 IMPORT/EXPORT
 ─────────────
 
 ✓ Export to JSON:
   try await DatabaseLogUtilities.exportToJSON(
       logger: logger,
       from: startDate,
       to: endDate,
       outputURL: fileURL
   )
 
 ✓ Import from JSON:
   try await DatabaseLogUtilities.importFromJSON(
       logger: logger,
       inputURL: fileURL
   )
 
 
 SYNC PATTERNS
 ─────────────
 
 ✓ Get changes since last sync:
   let changes = try await db.getLogEntries(from: lastSyncTime)
 
 ✓ Group by transaction:
   let byTx = Dictionary(grouping: changes, by: { $0.transactionId })
 
 ✓ Filter committed only:
   let committed = byTx.filter { (txId, entries) in
       entries.contains { $0.operationType == .transactionCommit }
   }
 
 ✓ Get data changes only:
   let dataChanges = entries.filter { entry in
       [.rowCreated, .rowDeleted, .rowUpdated].contains(entry.operationType)
   }
 
 
 CONFLICT RESOLUTION
 ───────────────────
 
 ✓ Last-write-wins:
   if local.timestamp > remote.timestamp {
       // Use local
   } else {
       // Use remote
   }
 
 ✓ Detect conflicts:
   let conflicts = localChanges.filter { local in
       remoteChanges.contains { remote in
           local.objectId == remote.objectId &&
           local.columnName == remote.columnName
       }
   }
 
 
 FILE LOCATIONS
 ──────────────
 
 Main DB:  /path/to/database.sqlite
 Log DB:   /path/to/database.log.sqlite
 Archive:  /path/to/archive-timestamp.log.sqlite
 
 
 PERFORMANCE TIPS
 ────────────────
 
 • Archive regularly (e.g., monthly)
 • Vacuum after archival
 • Batch sync instead of real-time
 • Use indexed queries (timestamp, transactionId, tableName)
 • Monitor log file size (~100KB per 1000 ops)
 
 
 COMMON QUERIES
 ──────────────
 
 ✓ Get all tables modified today:
   let today = Calendar.current.startOfDay(for: Date())
   let entries = try await db.getLogEntries(from: today)
   let tables = Set(entries.compactMap { $0.tableName })
 
 ✓ Get object history:
   let history = try await db.getLogEntries()
       .filter { $0.objectId == objectId }
       .sorted { $0.timestamp < $1.timestamp }
 
 ✓ Count operations by type:
   let entries = try await db.getLogEntries()
   let counts = Dictionary(grouping: entries, by: { $0.operationType })
       .mapValues { $0.count }
 
 ✓ Find failed transactions:
   let txIds = try await db.getLogTransactions()
   for txId in txIds {
       let entries = try await db.getLogEntries(transactionId: txId)
       let hasRollback = entries.contains { 
           $0.operationType == .transactionRollback 
       }
       if hasRollback {
           print("Failed: \(txId)")
       }
   }
 
 ✓ Get schema evolution:
   let schemaOps: [OperationType] = [
       .tableCreated, .columnAdded, .indexCreated, 
       .indexDropped, .foreignKeyAdded
   ]
   let evolution = try await db.getLogEntries()
       .filter { schemaOps.contains($0.operationType) }
       .sorted { $0.timestamp < $1.timestamp }
 
 
 ERROR HANDLING
 ──────────────
 
 • Logging uses `try?` to avoid failing transactions
 • Check `getLogger() != nil` to confirm logging is enabled
 • Logger errors are printed but don't throw
 • Integrity checks available via DatabaseLogUtilities
 
 
 TESTING
 ───────
 
 ✓ Verify logging is enabled:
   XCTAssertNotNil(await database.getLogger())
 
 ✓ Verify operations are logged:
   let before = (try? await db.getLogEntries())?.count ?? 0
   // ... perform operation
   let after = (try? await db.getLogEntries())?.count ?? 0
   XCTAssertGreaterThan(after, before)
 
 ✓ Verify transaction integrity:
   let issues = try await DatabaseLogUtilities.verifyIntegrity(logger)
   XCTAssertTrue(issues.isEmpty)
 
 
 BEST PRACTICES
 ──────────────
 
 ✓ DO:
   • Enable logging for production databases
   • Archive logs regularly
   • Use transaction IDs for atomic sync
   • Monitor log file growth
   • Verify integrity periodically
 
 ✗ DON'T:
   • Don't log sensitive data in metadata
   • Don't let logs grow unbounded
   • Don't sync incomplete transactions
   • Don't ignore integrity warnings
   • Don't delete logs without archiving
 
 
 ┌─────────────────────────────────────────────────────────────────────────┐
 │ For detailed examples, see DatabaseLoggingExamples.swift                │
 │ For utilities, see DatabaseLogUtilities.swift                           │
 │ For documentation, see README_LOGGING.md                                │
 └─────────────────────────────────────────────────────────────────────────┘
 
 */
