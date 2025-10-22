public enum Schema
{
    public struct Table: Sendable
    {
        public let name: String
        public let columns: [Column]
        public let indexes: [Index]
        
        public init(name: String, columns: [Column], indexes: [Index])
        {
            self.name = name
            self.columns = columns
            self.indexes = indexes
        }
    }

    public struct Column: Sendable
    {
        public let name: String
        public let storageClass: StorageClass
        public let positionInPrimaryKey: Int32?
        public let isNullable: Bool
        public let defaultValue: String?

        public init(name: String, type: Any.Type, positionInPrimaryKey: Int32? = nil, isNullable: Bool, defaultValue: SQLiteDefaultValueConvertible? = nil)
        {
            self.name = name
            self.storageClass = StorageClass(for: type)
            self.positionInPrimaryKey = positionInPrimaryKey
            self.isNullable = isNullable
            self.defaultValue = defaultValue?.asDefaultValueString
        }

        public init(name: String, storageClass: StorageClass, positionInPrimaryKey: Int32? = nil, isNullable: Bool, defaultValue: SQLiteDefaultValueConvertible? = nil)
        {
            self.name = name
            self.storageClass = storageClass
            self.positionInPrimaryKey = positionInPrimaryKey
            self.isNullable = isNullable
            self.defaultValue = defaultValue?.asDefaultValueString
        }
    }
    
    public struct Index: Sendable
    {
        public let name: String
        public let isUnique: Bool
        public let columns: [String]
        
        public init(name: String, isUnique: Bool, columns: [String])
        {
            self.name = name
            self.isUnique = isUnique
            self.columns = columns
        }
    }
}
