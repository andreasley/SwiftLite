import Foundation

extension Database
{
    
    /// Process external log entries received from distributed sync
    /// - Parameter entries: Array of log entries grouped by transaction ID
    /// - Note: Entries should be sorted by timestamp and grouped by transaction
    public func processExternalLogEntries(_ entries: [DatabaseLogger.LogEntry]) async throws
    {
        guard !entries.isEmpty else { return }
        
        // Group entries by transaction ID
        let groupedByTransaction = Dictionary(grouping: entries) { $0.transactionId }
        
        // Sort transaction IDs by the earliest timestamp in each group
        let sortedTransactionIds = groupedByTransaction.keys.sorted { transactionId1, transactionId2 in
            let firstTimestamp1 = groupedByTransaction[transactionId1]?.first?.timestamp ?? Date.distantPast
            let firstTimestamp2 = groupedByTransaction[transactionId2]?.first?.timestamp ?? Date.distantPast
            return firstTimestamp1 < firstTimestamp2
        }
        
        // Process each transaction in order
        for transactionId in sortedTransactionIds {
            guard let transactionEntries = groupedByTransaction[transactionId] else { continue }
            
            // Sort entries within transaction by timestamp
            let sortedEntries = transactionEntries.sorted { $0.timestamp < $1.timestamp }
            
            try await processTransaction(entries: sortedEntries, transactionId: transactionId)
        }
    }
    
    /// Process a single transaction's worth of log entries
    internal func processTransaction(entries: [DatabaseLogger.LogEntry], transactionId: UUID) async throws
    {
        try await gate.run {
            print("▶️ BEGINNING EXTERNAL LOG REPLAY TRANSACTION (\(transactionId))")
            
            // Group by operation type to handle schema changes first
            let schemaEntries = entries.filter { entry in
                switch entry.operationType {
                case .tableCreated,
                        .columnAdded,
                        .indexCreated,
                        .indexDropped:
                    return true
                default:
                    return false
                }
            }
            
            let dataEntries = entries.filter { entry in
                switch entry.operationType {
                case .rowCreated,
                        .rowDeleted,
                        .fieldUpdated:
                    return true
                default:
                    return false
                }
            }
            
            // Process schema changes first
            if !schemaEntries.isEmpty {
                try await processSchemaEntries(schemaEntries, transactionId: transactionId)
            }
            
            // Then process data changes
            if !dataEntries.isEmpty {
                try await processDataEntries(dataEntries, transactionId: transactionId)
            }
            
            print("✅ COMPLETED EXTERNAL LOG REPLAY TRANSACTION (\(transactionId))")
        }
    }
    
    /// Process schema change log entries
    private func processSchemaEntries(_ entries: [DatabaseLogger.LogEntry], transactionId: UUID) async throws
    {
        try self.run("BEGIN")
        
        do {
            for entry in entries {
                guard let tableName = entry.tableName else {
                    print("⚠️ Skipping schema entry without table name: \(entry.operationType)")
                    continue
                }
                
                switch entry.operationType {
                case DatabaseLogger.OperationType.tableCreated:
                    print("📋 Replaying: Table created - \(tableName)")
                    let createTableStatement = """
                    CREATE TABLE IF NOT EXISTS "\(tableName)" (
                        "id" TEXT,
                        PRIMARY KEY(id)
                    ) STRICT, WITHOUT ROWID;
                    """
                    try run(createTableStatement)
                    
                    
                case DatabaseLogger.OperationType.columnAdded:
                    guard let columnName = entry.columnName else {
                        print("⚠️ Skipping column addition without column name")
                        continue
                    }
                    
                    // Extract storage class from metadata
                    var storageClass = "TEXT" // default
                    if let metadataJSON = entry.metadata,
                       let metadataData = metadataJSON.data(using: .utf8),
                       let metadata = try? JSONSerialization.jsonObject(with: metadataData) as? [String: Any],
                       let storageClassValue = metadata["storageClass"] as? String {
                        storageClass = storageClassValue.uppercased()
                    }
                    
                    print("📋 Replaying: Column added - \(tableName).\(columnName) (\(storageClass))")
                    
                    // Check if column already exists
                    let existingColumns = try getColumns(tableName: tableName)
                    if !existingColumns.contains(where: { $0.name == columnName }) {
                        let alterStatement = "ALTER TABLE \"\(tableName)\" ADD COLUMN \"\(columnName)\" \(storageClass)"
                        try run(alterStatement)
                    } else {
                        print("ℹ️ Column \(tableName).\(columnName) already exists, skipping")
                    }
                    
                case DatabaseLogger.OperationType.indexCreated:
                    guard let metadataJSON = entry.metadata,
                          let metadataData = metadataJSON.data(using: .utf8),
                          let metadata = try? JSONSerialization.jsonObject(with: metadataData) as? [String: Any],
                          let indexName = metadata["indexName"] as? String,
                          let columns = metadata["columns"] as? [String] else {
                        print("⚠️ Skipping index creation without required metadata")
                        continue
                    }
                    
                    let isUnique = (metadata["isUnique"] as? Bool) ?? false
                    
                    print("📋 Replaying: Index created - \(indexName) on \(tableName)")
                    
                    // Check if index already exists
                    let existingIndexes = try getIndexes(tableName: tableName)
                    if !existingIndexes.contains(where: { $0.name == indexName }) {
                        let uniqueKeyword = isUnique ? "UNIQUE " : ""
                        let createIndexStatement = "CREATE \(uniqueKeyword)INDEX IF NOT EXISTS \"\(indexName)\" ON \"\(tableName)\"(\(columns.joined(separator: ", ")))"
                        try run(createIndexStatement)
                    } else {
                        print("ℹ️ Index \(indexName) already exists, skipping")
                    }
                    
                case DatabaseLogger.OperationType.indexDropped:
                    guard let metadataJSON = entry.metadata,
                          let metadataData = metadataJSON.data(using: .utf8),
                          let metadata = try? JSONSerialization.jsonObject(with: metadataData) as? [String: Any],
                          let indexName = metadata["indexName"] as? String else {
                        print("⚠️ Skipping index drop without index name")
                        continue
                    }
                    
                    print("📋 Replaying: Index dropped - \(indexName)")
                    
                    // Check if index exists before dropping
                    let existingIndexes = try getIndexes(tableName: tableName)
                    if existingIndexes.contains(where: { $0.name == indexName }) {
                        try run("DROP INDEX \"\(indexName)\"")
                    } else {
                        print("ℹ️ Index \(indexName) doesn't exist, skipping")
                    }
                    
                default:
                    break
                }
            }
            
            try self.run("COMMIT")
            print("✅ COMMITTED SCHEMA REPLAY TRANSACTION")
        } catch {
            try? self.run("ROLLBACK")
            print("✴️ ROLLED BACK SCHEMA REPLAY TRANSACTION")
            throw error
        }
    }
    
    /// Process data change log entries
    private func processDataEntries(_ entries: [DatabaseLogger.LogEntry], transactionId: UUID) async throws
    {
        try self.run("BEGIN")
        
        do {
            try self.setPragma(name: "defer_foreign_keys", value: "ON")
            
            // Group data entries by object ID to reconstruct operations
            // Use a custom key type that conforms to Hashable
            struct ObjectKey: Hashable {
                let tableName: String
                let objectId: UUID
            }
            
            let groupedByObject = Dictionary(grouping: entries.compactMap { entry -> (ObjectKey, DatabaseLogger.LogEntry)? in
                guard let tableName = entry.tableName, let objectId = entry.objectId else {
                    return nil
                }
                return (ObjectKey(tableName: tableName, objectId: objectId), entry)
            }) { $0.0 }
            
            for (key, keyedEntries) in groupedByObject {
                let tableName = key.tableName
                let objectId = key.objectId
                let objectEntries = keyedEntries.map { $0.1 }
                
                let sortedObjectEntries = objectEntries.sorted { $0.timestamp < $1.timestamp }
                
                // Determine the operation type
                let hasRowCreated = sortedObjectEntries.contains { $0.operationType == DatabaseLogger.OperationType.rowCreated }
                let hasRowDeleted = sortedObjectEntries.contains { $0.operationType == DatabaseLogger.OperationType.rowDeleted }
                let fieldUpdates = sortedObjectEntries.filter { $0.operationType == DatabaseLogger.OperationType.fieldUpdated }
                
                if hasRowDeleted {
                    // Delete operation
                    print("📋 Replaying: Row deleted - \(tableName)[\(objectId)]")
                    let deleteStatement = SQLStatementPreset.Delete(
                        table: tableName,
                        conditions: [SQLCondition(field: "id", value: .string(objectId.uuidString))]
                    )
                    try run(deleteStatement.sqlStatement)
                    
                } else if hasRowCreated {
                    // Create operation - collect all field values
                    var fields: [String: SQLValue] = ["id": .string(objectId.uuidString)]
                    
                    for fieldUpdate in fieldUpdates {
                        guard let columnName = fieldUpdate.columnName,
                              let newValue = fieldUpdate.newValue else { continue }
                        fields[columnName] = newValue
                    }
                    
                    print("📋 Replaying: Row created - \(tableName)[\(objectId)] with \(fields.count) fields")
                    
                    let insertStatement = SQLStatementPreset.Insert(table: tableName, updatedFields: fields)
                    try execute(insertStatement.sqlStatement)
                    
                } else if !fieldUpdates.isEmpty {
                    // Update operation - apply field changes
                    var fields: [String: SQLValue] = [:]
                    
                    for fieldUpdate in fieldUpdates {
                        guard let columnName = fieldUpdate.columnName,
                              let newValue = fieldUpdate.newValue else { continue }
                        fields[columnName] = newValue
                    }
                    
                    if !fields.isEmpty {
                        print("📋 Replaying: Row updated - \(tableName)[\(objectId)] with \(fields.count) fields")
                        
                        let updateStatement = SQLStatementPreset.Update(
                            table: tableName,
                            updatedFields: fields,
                            condition: SQLCondition(field: "id", value: .string(objectId.uuidString))
                        )
                        try execute(updateStatement.sqlStatement)
                    }
                }
            }
            
            try self.run("COMMIT")
            print("✅ COMMITTED DATA REPLAY TRANSACTION")
        } catch {
            try? self.run("ROLLBACK")
            print("✴️ ROLLED BACK DATA REPLAY TRANSACTION")
            throw error
        }
    }
}
