public nonisolated enum RequiredSchema
{
    // TODO: Decide if `check` should be added (e.g. to enfore that columns for BOOL values have `CHECK (is_active IN (0, 1))`)
    
    public struct Table: Sendable, Hashable, Equatable
    {
        public let name: String
        public let columns: [Column]
        public let indexes: [Index]
        public let defaultSelectStatement: SQLStatementPreset.Select
        
        public init(name: String, columns: [Column], indexes: [Index] = [])
        {
            self.name = name
            self.columns = columns
            self.indexes = indexes
            self.defaultSelectStatement = .init(table: name, columns: columns.map(\.name))
        }
    }

    public struct Column: Sendable, Hashable, Equatable
    {
        public let name: String
        public let storageClass: StorageClass
        public let referencedTable: String?

        public init(name: String, type: Any.Type, referencedTable: String? = nil)
        {
            self.name = name
            self.storageClass = StorageClass(for: type)
            self.referencedTable = referencedTable
        }

        public init(name: String, storageClass: StorageClass, referencedTable: String? = nil)
        {
            self.name = name
            self.storageClass = storageClass
            self.referencedTable = referencedTable
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
}
