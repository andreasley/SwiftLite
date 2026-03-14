public nonisolated enum RequiredSchema
{
    // TODO: Decide if `check` should be added (e.g. to enfore that columns for BOOL values have `CHECK (is_active IN (0, 1))`)
    
    public struct Table: Sendable, Hashable, Equatable
    {
        public let name: String
        public let columns: [Column]
        public let indexes: [Index]
        public let foreignKeys: [ForeignKey]
        public let defaultSelectStatement: SQLStatementPreset.Select
        
        public init(name: String, columns: [Column], indexes: [Index] = [], foreignKeys: [ForeignKey] = [])
        {
            self.name = name
            self.columns = columns
            self.indexes = indexes
            self.foreignKeys = foreignKeys
            self.defaultSelectStatement = .init(table: name, columns: columns.map(\.name))
        }
    }

    public struct Column: Sendable, Hashable, Equatable
    {
        public let name: String
        public let storageClass: StorageClass

        public init(name: String, type: Any.Type)
        {
            self.name = name
            self.storageClass = StorageClass(for: type)
        }

        public init(name: String, storageClass: StorageClass)
        {
            self.name = name
            self.storageClass = storageClass
        }
    }
    
    public struct Index: Sendable, Hashable, Equatable
    {
        public let name: String
        public let isUnique: Bool
        public let columns: [String]
        
        public init(name: String, isUnique: Bool, columns: [Column])
        {
            self.name = name
            self.isUnique = isUnique
            self.columns = columns.map { $0.name }
        }
    }
    
    public struct ForeignKey: Sendable, Hashable, Equatable
    {
        public let column: String
        public let referencedTable: String
        public let referencedColumn: String
        
        public init(column: String, referencedTable: String, referencedColumn: String = "id")
        {
            self.column = column
            self.referencedTable = referencedTable
            self.referencedColumn = referencedColumn
        }
    }
}
