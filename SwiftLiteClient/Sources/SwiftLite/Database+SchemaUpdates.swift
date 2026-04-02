import Foundation

extension Database
{
    func updateTableIfNecessary(existingTable: ExistingSchema.Table, table: RequiredSchema.Table) async throws
    {
        // Get existing schema details
        let existingColumns = try getColumns(tableName: table.name)
        let existingIndexes = try getIndexes(tableName: table.name)
        
        // Compare table properties
        let needsRecreation = existingTable.isStrict != true || existingTable.isWithoutRowId != true
        
        // Compare columns
        var columnsToAdd = [RequiredSchema.Column]()
        var columnTypeChanged = false
        
        // Build a map of existing columns for quick lookup
        let existingColumnMap = Dictionary(uniqueKeysWithValues: existingColumns.map { ($0.name, $0) })
        
        // Check for columns that need to be added or have changed types
        for requiredColumn in table.columns {
            if let existingColumn = existingColumnMap[requiredColumn.name] {
                // Column exists, check if type matches
                if existingColumn.storageClass != requiredColumn.storageClass {
                    print("⚠️ Column '\(requiredColumn.name)' type changed from \(existingColumn.storageClass.rawValue) to \(requiredColumn.storageClass.rawValue)")
                    columnTypeChanged = true
                }
                
                // Check if collation matches
                let requiredCollation = requiredColumn.collation?.uppercased()
                let existingCollation = existingColumn.collation?.uppercased()
                
                if requiredCollation != existingCollation {
                    print("⚠️ Column '\(requiredColumn.name)' collation changed from \(existingCollation ?? "none") to \(requiredCollation ?? "none")")
                    columnTypeChanged = true
                }
            } else {
                // Column doesn't exist, needs to be added
                columnsToAdd.append(requiredColumn)
            }
        }
        
        // Compare indexes
        var indexesToAdd = [RequiredSchema.Index]()
        var indexesToRemove = [ExistingSchema.Index]()
        
        // Filter out system-generated indexes (like primary key indexes)
        let userCreatedIndexes = existingIndexes.filter { $0.origin == .createIndex }
        
        let existingIndexMap = Dictionary(uniqueKeysWithValues: userCreatedIndexes.map { ($0.name, $0) })
        let requiredIndexMap = Dictionary(uniqueKeysWithValues: table.indexes.map { ($0.name, $0) })
        
        for requiredIndex in table.indexes {
            if let existingIndex = existingIndexMap[requiredIndex.name] {
                // Index exists, check if it matches
                let columnsMatch = existingIndex.columns == requiredIndex.columns
                let uniquenessMatches = existingIndex.isUnique == requiredIndex.isUnique
                
                if !columnsMatch || !uniquenessMatches {
                    // Index needs to be recreated
                    indexesToRemove.append(existingIndex)
                    indexesToAdd.append(requiredIndex)
                }
            } else {
                // Index doesn't exist
                indexesToAdd.append(requiredIndex)
            }
        }
        
        // Check for indexes to remove
        for existingIndex in userCreatedIndexes {
            if requiredIndexMap[existingIndex.name] == nil {
                indexesToRemove.append(existingIndex)
            }
        }
        
        // Decide on migration strategy
        if needsRecreation || columnTypeChanged {
            // Would need to recreate the table, which is not supported
            print("⛔️ Schema migration failed; Table '\(table.name)' requires structural changes")
            throw Error.failedToMigrateSchema
        } else {
            // Can use simpler ALTER TABLE operations
            
            // Add new columns
            for column in columnsToAdd {
                print("➕ Adding column '\(column.name)' to table '\(table.name)'")
                
                var columnDef = "\"\(column.name)\" \(column.storageClass.rawValue.uppercased())"
                if let collation = column.collation {
                    columnDef += " COLLATE \(collation.uppercased())"
                }
                
                let alterStatement = "ALTER TABLE \"\(table.name)\" ADD COLUMN \(columnDef)"
                try run(alterStatement)
                
                // Collect column addition for batch logging
                if currentTransactionId != nil {
                    var metadata: [String: any Sendable] = ["storageClass": column.storageClass.rawValue]
                    if let collation = column.collation {
                        metadata["collation"] = collation
                    }
                    
                    pendingSchemaChanges.append(
                        SyncClient.SchemaChange(
                            operationType: .columnAdded,
                            tableName: table.name,
                            columnName: column.name,
                            metadata: metadata
                        )
                    )
                }
            }
            
            // Update indexes
            for index in indexesToRemove {
                print("🗑️ Dropping index '\(index.name)'")
                try run("DROP INDEX \"\(index.name)\"")
                
                // Collect index removal for batch logging
                if currentTransactionId != nil {
                    pendingSchemaChanges.append(
                        SyncClient.SchemaChange(
                            operationType: .indexDropped,
                            tableName: table.name,
                            metadata: ["indexName": index.name]
                        )
                    )
                }
            }
            
            for index in indexesToAdd {
                print("➕ Creating index '\(index.name)'")
                let createIndexStatement = "CREATE \(index.isUnique ? "UNIQUE " : "")INDEX \"\(index.name)\" ON \"\(table.name)\"(\(index.columns.joined(separator: ", ")))"
                try run(createIndexStatement)
                
                // Collect index creation for batch logging
                if currentTransactionId != nil {
                    pendingSchemaChanges.append(
                        SyncClient.SchemaChange(
                            operationType: .indexCreated,
                            tableName: table.name,
                            metadata: [
                                "indexName": index.name,
                                "isUnique": index.isUnique,
                                "columns": index.columns
                            ]
                        )
                    )
                }
            }
        }
    }
    
    func createTable(_ table: RequiredSchema.Table) async throws
    {
        let createTableStatement = createTableStatement(for: table)
        let createIndexStatements = createIndexStatements(for: table)
        print(createTableStatement)
        try self.run(createTableStatement)
        
        // Collect table creation for batch logging
        if currentTransactionId != nil {
            pendingSchemaChanges.append(
                SyncClient.SchemaChange(
                    operationType: .tableCreated,
                    tableName: table.name
                )
            )
            
            // Collect each column addition separately
            for column in table.columns {
                var metadata: [String: any Sendable] = ["storageClass": column.storageClass.rawValue]
                
                // Include collation if specified
                if let collation = column.collation {
                    metadata["collation"] = collation
                }
                
                // Include referenced table if this column has a foreign key
                if let referencedTable = column.referencedTable {
                    metadata["referencedTable"] = referencedTable
                    metadata["referencedColumn"] = "id"
                }
                
                pendingSchemaChanges.append(
                    SyncClient.SchemaChange(
                        operationType: .columnAdded,
                        tableName: table.name,
                        columnName: column.name,
                        metadata: metadata
                    )
                )
            }
        }
        
        for createIndexStatement in createIndexStatements {
            print(createIndexStatement)
            try self.run(createIndexStatement)
        }
        
        // Collect index creations for batch logging
        if currentTransactionId != nil {
            for index in table.indexes {
                pendingSchemaChanges.append(
                    SyncClient.SchemaChange(
                        operationType: .indexCreated,
                        tableName: table.name,
                        metadata: [
                            "indexName": index.name,
                            "isUnique": index.isUnique,
                            "columns": index.columns
                        ]
                    )
                )
            }
        }
    }
    
    func getUserDefinedTables() throws -> [ExistingSchema.Table]
    {
        let tables = try pragma("table_list", expecting: ExistingSchema.Table.self)
        return tables.filter { $0.isUserDefined }
    }
    
    func getColumns(tableName: String) throws -> [ExistingSchema.Column]
    {
        // First get basic column info
        var columns = try pragma("table_info(\(tableName))", expecting: ExistingSchema.Column.self)
        
        // Get the CREATE TABLE statement to extract collation info
        let sql = SQLStatement(
            text: "SELECT sql FROM sqlite_schema WHERE type='table' AND name=?;",
            values: [.string(tableName)]
        )
        
        let rows = try execute(sql)
        
        // Parse collation from CREATE TABLE statement if available
        if let firstRow = rows.first,
           let createTableSQL: String = try? firstRow.get("sql") {
            columns = columns.map { column in
                column.withCollation(extractCollation(for: column.name, from: createTableSQL))
            }
        }
        
        return columns
    }
    
    /// Extract collation for a specific column from a CREATE TABLE statement
    private func extractCollation(for columnName: String, from createTableSQL: String) -> String?
    {
        // Look for pattern like: "columnName" TEXT COLLATE NOCASE
        // or: columnName TEXT COLLATE NOCASE
        let patterns = [
            "\"\(columnName)\"\\s+\\w+\\s+COLLATE\\s+(\\w+)",  // Quoted column name
            "\\b\(columnName)\\b\\s+\\w+\\s+COLLATE\\s+(\\w+)"  // Unquoted column name
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: createTableSQL, range: NSRange(createTableSQL.startIndex..., in: createTableSQL)),
               let collationRange = Range(match.range(at: 1), in: createTableSQL) {
                return String(createTableSQL[collationRange])
            }
        }
        
        return nil
    }
    
    func getIndexes(tableName: String) throws -> [ExistingSchema.Index]
    {
        var indexes = [ExistingSchema.Index]()
        
        let indexesWithoutColumns = try pragma("index_list(\(tableName))", expecting: ExistingSchema.Index.self)
        
        for indexWithoutColumn in indexesWithoutColumns {
            let columnsInIndex = try pragma("index_info(\(indexWithoutColumn.name));", expecting: ExistingSchema.IndexColumn.self)
            indexes.append(indexWithoutColumn.withColumns(columnsInIndex))
        }
        
        return indexes
    }
    
    func createIndexStatements(for table: RequiredSchema.Table) -> [String]
    {
        var createIndexStatements = [String]()
        
        for index in table.indexes {
            let statement = "CREATE \(index.isUnique ? "UNIQUE " : "")INDEX \(index.name) ON \(table.name)(\(index.columns.joined(separator: ", ")));"
            createIndexStatements.append(statement)
        }
        
        return createIndexStatements
    }
    
    func createTableStatement(for table: RequiredSchema.Table) -> String
    {
        var columns = [String]()
        
        for column in table.columns
        {
            var columnDefinition = "\"\(column.name)\" \(column.storageClass.rawValue.uppercased())"
            
            // Add collation if specified
            if let collation = column.collation {
                columnDefinition += " COLLATE \(collation.uppercased())"
            }
            
            // Check if this column has a foreign key reference
            if let referencedTable = column.referencedTable {
                columnDefinition += " REFERENCES \(referencedTable) (id)"
            }
            
            columns.append(columnDefinition)
        }
        
        let columnDefinitions = columns.joined(separator: ",\n    ")
        
        let createTableStatement = """
        CREATE TABLE "\(table.name)" (
            \(columnDefinitions),
            PRIMARY KEY(id)
        ) STRICT, WITHOUT ROWID;
        """
        
        // Note: `STRICT` is required, because when creating a `Database.Row` to forward the fetched data to object initializers, the storage values are created by switching on the SQLite column type. STRICT ensures the column type is set.
        
        return createTableStatement
    }
}
