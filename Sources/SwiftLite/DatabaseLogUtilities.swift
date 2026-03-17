import Foundation
import SQLite3

/// Utilities for maintaining and working with the database log
public struct DatabaseLogUtilities {
    
    /// Statistics about the log database
    public struct LogStatistics: Sendable {
        public let totalEntries: Int
        public let oldestEntry: Date?
        public let newestEntry: Date?
        public let totalTransactions: Int
        public let entriesByType: [DatabaseLogger.OperationType: Int]
        public let fileSize: Int64 // in bytes
        
        public var fileSizeMB: Double {
            Double(fileSize) / 1_048_576.0
        }
    }
    
    /// Archive options for log maintenance
    public struct ArchiveOptions: Sendable {
        public let olderThan: Date
        public let deleteAfterArchive: Bool
        public let archiveURL: URL
        
        public init(olderThan: Date, deleteAfterArchive: Bool = true, archiveURL: URL) {
            self.olderThan = olderThan
            self.deleteAfterArchive = deleteAfterArchive
            self.archiveURL = archiveURL
        }
    }
    
    /// Get statistics about the log database
    public static func getStatistics(logger: DatabaseLogger, logFileURL: URL) async throws -> LogStatistics {
        let allEntries = try await logger.getEntries()
        
        let totalEntries = allEntries.count
        let oldestEntry = allEntries.min(by: { $0.timestamp < $1.timestamp })?.timestamp
        let newestEntry = allEntries.max(by: { $0.timestamp < $1.timestamp })?.timestamp
        
        let uniqueTransactions = Set(allEntries.map { $0.transactionId })
        let totalTransactions = uniqueTransactions.count
        
        var entriesByType: [DatabaseLogger.OperationType: Int] = [:]
        for entry in allEntries {
            entriesByType[entry.operationType, default: 0] += 1
        }
        
        let fileSize = try FileManager.default.attributesOfItem(atPath: logFileURL.path)[.size] as? Int64 ?? 0
        
        return LogStatistics(
            totalEntries: totalEntries,
            oldestEntry: oldestEntry,
            newestEntry: newestEntry,
            totalTransactions: totalTransactions,
            entriesByType: entriesByType,
            fileSize: fileSize
        )
    }
    
    /// Archive old log entries to a separate file
    public static func archiveEntries(
        logger: DatabaseLogger,
        options: ArchiveOptions
    ) async throws {
        // Get entries older than the specified date
        let entriesToArchive = try await logger.getEntries(to: options.olderThan)
        
        guard !entriesToArchive.isEmpty else {
            print("No entries to archive")
            return
        }
        
        print("Archiving \(entriesToArchive.count) entries older than \(options.olderThan)")
        
        // Create archive logger
        let archiveLogger = try await DatabaseLogger(logFileURL: options.archiveURL)
        
        // Write entries to archive
        try await archiveLogger.logBatch(entriesToArchive)
        
        try await archiveLogger.close()
        
        print("Archived entries to \(options.archiveURL.path)")
        
        // Delete from main log if requested
        if options.deleteAfterArchive {
            try await deleteEntries(logger: logger, olderThan: options.olderThan)
        }
    }
    
    /// Delete entries older than a specified date
    public static func deleteEntries(
        logger: DatabaseLogger,
        olderThan: Date
    ) async throws {
        // This requires direct SQL access to the logger's database
        // For now, this is a placeholder showing the concept
        // In a production implementation, you'd add a delete method to DatabaseLogger
        
        print("⚠️ Deletion of log entries requires a deleteEntries method on DatabaseLogger")
        print("   Consider archiving instead of deleting for data integrity")
    }
    
    /// Vacuum the log database to reclaim space
    public static func vacuum(logFileURL: URL) throws {
        // Open a temporary connection to vacuum
        var pointer: OpaquePointer?
        var flags = [SQLITE_OPEN_READWRITE, SQLITE_OPEN_CREATE, SQLITE_OPEN_FULLMUTEX] // see https://sqlite.org/c3ref/open.html

        let openStatus = sqlite3_open_v2(logFileURL.path, &pointer, flags.reduce(0, |), nil)
        
        guard let pointer, openStatus == SQLiteStatus.ok else {
            throw DatabaseLogger.Error.failedToOpen(SQLiteStatus(openStatus))
        }
        
        defer { sqlite3_close(pointer) }
        
        let result = sqlite3_exec(pointer, "VACUUM", nil, nil, nil)
        
        guard result == SQLiteStatus.ok else {
            let errmsg = String(cString: sqlite3_errmsg(pointer))
            throw DatabaseLogger.Error.failedToLog("Vacuum failed: \(errmsg)")
        }
        
        print("✅ Log database vacuumed successfully")
    }
    
    /// Export log entries to JSON format
    public static func exportToJSON(
        logger: DatabaseLogger,
        from startDate: Date? = nil,
        to endDate: Date? = nil,
        outputURL: URL
    ) async throws {
        let entries = try await logger.getEntries(from: startDate, to: endDate)
        
        let jsonObjects = entries.map { entry -> [String: Any] in
            var obj: [String: Any] = [
                "id": entry.id.uuidString,
                "timestamp": entry.timestamp.timeIntervalSince1970,
                "transactionId": entry.transactionId.uuidString,
                "operationType": entry.operationType.rawValue
            ]
            
            if let tableName = entry.tableName {
                obj["tableName"] = tableName
            }
            if let objectId = entry.objectId {
                obj["objectId"] = objectId.uuidString
            }
            if let columnName = entry.columnName {
                obj["columnName"] = columnName
            }
            if let oldValue = entry.oldValue {
                obj["oldValue"] = oldValue
            }
            if let newValue = entry.newValue {
                obj["newValue"] = newValue
            }
            if let metadata = entry.metadata {
                obj["metadata"] = metadata
            }
            
            return obj
        }
        
        let jsonData = try JSONSerialization.data(
            withJSONObject: jsonObjects,
            options: [.prettyPrinted, .sortedKeys]
        )
        
        try jsonData.write(to: outputURL)
        
        print("✅ Exported \(entries.count) entries to \(outputURL.path)")
    }
    
    /// Import log entries from JSON format
    public static func importFromJSON(
        logger: DatabaseLogger,
        inputURL: URL
    ) async throws {
        let jsonData = try Data(contentsOf: inputURL)
        
        guard let jsonObjects = try JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else {
            throw DatabaseLogger.Error.failedToLog("Invalid JSON format")
        }
        
        var entries: [DatabaseLogger.LogEntry] = []
        
        for obj in jsonObjects {
            guard let idString = obj["id"] as? String,
                  let id = UUID(uuidString: idString),
                  let timestampInterval = obj["timestamp"] as? TimeInterval,
                  let transactionIdString = obj["transactionId"] as? String,
                  let transactionId = UUID(uuidString: transactionIdString),
                  let operationTypeString = obj["operationType"] as? String,
                  let operationType = DatabaseLogger.OperationType(rawValue: operationTypeString)
            else {
                continue
            }
            
            let timestamp = Date(timeIntervalSince1970: timestampInterval)
            let tableName = obj["tableName"] as? String
            let objectId = (obj["objectId"] as? String).flatMap { UUID(uuidString: $0) }
            let columnName = obj["columnName"] as? String
            let oldValue = obj["oldValue"] as? String
            let newValue = obj["newValue"] as? String
            let metadata = obj["metadata"] as? String
            
            entries.append(DatabaseLogger.LogEntry(
                id: id,
                timestamp: timestamp,
                transactionId: transactionId,
                operationType: operationType,
                tableName: tableName,
                objectId: objectId,
                columnName: columnName,
                oldValue: oldValue,
                newValue: newValue,
                metadata: metadata
            ))
        }
        
        try await logger.logBatch(entries)
        
        print("✅ Imported \(entries.count) entries from \(inputURL.path)")
    }
    
    /// Verify log integrity
    public static func verifyIntegrity(logger: DatabaseLogger) async throws -> [String] {
        var issues: [String] = []
        
        let allEntries = try await logger.getEntries()
        let transactions = try await logger.getTransactions()
        
        // Check that all transactions have begin/commit or begin/rollback
        for transactionId in transactions {
            let transactionEntries = allEntries.filter { $0.transactionId == transactionId }
            
            let hasBegin = transactionEntries.contains { $0.operationType == .transactionBegin }
            let hasCommit = transactionEntries.contains { $0.operationType == .transactionCommit }
            let hasRollback = transactionEntries.contains { $0.operationType == .transactionRollback }
            
            if !hasBegin {
                issues.append("Transaction \(transactionId) is missing begin entry")
            }
            
            if !hasCommit && !hasRollback {
                issues.append("Transaction \(transactionId) is missing commit or rollback entry")
            }
            
            if hasCommit && hasRollback {
                issues.append("Transaction \(transactionId) has both commit and rollback entries")
            }
        }
        
        // Check for orphaned entries (entries with transaction ID not in transactions list)
        let transactionSet = Set(transactions)
        let orphanedEntries = allEntries.filter { !transactionSet.contains($0.transactionId) }
        
        if !orphanedEntries.isEmpty {
            issues.append("Found \(orphanedEntries.count) orphaned entries with unknown transaction IDs")
        }
        
        // Check temporal ordering within transactions
        for transactionId in transactions {
            let transactionEntries = allEntries
                .filter { $0.transactionId == transactionId }
                .sorted { $0.timestamp < $1.timestamp }
            
            if let beginEntry = transactionEntries.first(where: { $0.operationType == .transactionBegin }),
               let endEntry = transactionEntries.first(where: { 
                   $0.operationType == .transactionCommit || $0.operationType == .transactionRollback 
               }) {
                if beginEntry.timestamp > endEntry.timestamp {
                    issues.append("Transaction \(transactionId) has end before begin")
                }
            }
        }
        
        return issues
    }
    
    /// Generate a summary report of log activity
    public static func generateReport(
        logger: DatabaseLogger,
        from startDate: Date? = nil,
        to endDate: Date? = nil
    ) async throws -> String {
        let entries = try await logger.getEntries(from: startDate, to: endDate)
        
        var report = "# Database Log Report\n\n"
        
        if let startDate {
            report += "From: \(startDate)\n"
        }
        if let endDate {
            report += "To: \(endDate)\n"
        }
        report += "\n"
        
        report += "## Summary\n\n"
        report += "Total Entries: \(entries.count)\n"
        
        let transactions = Set(entries.map { $0.transactionId })
        report += "Total Transactions: \(transactions.count)\n\n"
        
        report += "## Operations by Type\n\n"
        let operationCounts = Dictionary(grouping: entries, by: { $0.operationType })
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }
        
        for (operation, count) in operationCounts {
            report += "- \(operation.rawValue): \(count)\n"
        }
        
        report += "\n## Activity by Table\n\n"
        let tableCounts = Dictionary(grouping: entries.compactMap { $0.tableName }, by: { $0 })
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }
        
        for (table, count) in tableCounts {
            report += "- \(table): \(count) operations\n"
        }
        
        report += "\n## Transaction Status\n\n"
        var committed = 0
        var rolledBack = 0
        var incomplete = 0
        
        for transactionId in transactions {
            let transactionEntries = entries.filter { $0.transactionId == transactionId }
            if transactionEntries.contains(where: { $0.operationType == .transactionCommit }) {
                committed += 1
            } else if transactionEntries.contains(where: { $0.operationType == .transactionRollback }) {
                rolledBack += 1
            } else {
                incomplete += 1
            }
        }
        
        report += "- Committed: \(committed)\n"
        report += "- Rolled Back: \(rolledBack)\n"
        report += "- Incomplete: \(incomplete)\n"
        
        return report
    }
}

// MARK: - Example Usage

func maintenanceExample() async throws {
    let dbURL = URL(fileURLWithPath: "/path/to/database.sqlite")
    let logURL = dbURL.deletingPathExtension()
        .appendingPathComponent("log")
        .appendingPathExtension("sqlite")
    
    let database = try await Database(storage: .file(dbURL))
    guard let logger = await database.getLogger() else { return }
    
    // Get statistics
    let stats = try await DatabaseLogUtilities.getStatistics(logger: logger, logFileURL: logURL)
    print("Log Statistics:")
    print("  Total entries: \(stats.totalEntries)")
    print("  Total transactions: \(stats.totalTransactions)")
    print("  File size: \(String(format: "%.2f", stats.fileSizeMB)) MB")
    
    // Generate report
    let report = try await DatabaseLogUtilities.generateReport(logger: logger)
    print(report)
    
    // Archive old entries (older than 30 days)
    let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 3600)
    let archiveURL = dbURL.deletingLastPathComponent()
        .appendingPathComponent("archive-\(Date().timeIntervalSince1970).log.sqlite")
    
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
    
    // Verify integrity
    let issues = try await DatabaseLogUtilities.verifyIntegrity(logger: logger)
    if issues.isEmpty {
        print("✅ Log integrity verified")
    } else {
        print("⚠️ Log integrity issues found:")
        for issue in issues {
            print("  - \(issue)")
        }
    }
    
    try await database.close()
}
