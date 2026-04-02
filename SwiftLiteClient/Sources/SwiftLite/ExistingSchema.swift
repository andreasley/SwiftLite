import SQLite3

public nonisolated enum ExistingSchema
{
    public struct Table: Sendable, InitializableFromResultRow, Hashable
    {
        public enum TableType: String, Sendable, Storable {
            case table
            case view
            case shadow
            case virtual
            case unknown
        }
        
        public let schema: String
        public let name: String
        public let type: TableType
        public let numberOfColumns: Int32
        public let isWithoutRowId: Bool
        public let isStrict: Bool
        
        public let isUserDefined: Bool
        
        public init(db: Database, row: Database.Row) throws
        {
            // See https://sqlite.org/pragma.html#pragma_table_list
            /*
             Columns returned by the table_list pragma include these:
             - schema: the schema in which the table or view appears (for example "main" or "temp").
             - name: the name of the table or view.
             - type: the type of object - one of "table", "view", "shadow" (for shadow tables), or "virtual" for virtual tables.
             - ncol: the number of columns in the table, including generated columns and hidden columns.
             - wr: 1 if the table is a WITHOUT ROWID table or 0 if is not.
             - strict: 1 if the table is a STRICT table or 0 if it is not.
             Additional columns will likely be added in future releases.
             */
            
            self.schema = try row.get("schema")
            self.name = try row.get("name")
            self.type = try row.get("type")
            self.numberOfColumns = try row.get("ncol")
            self.isWithoutRowId = try row.get("wr")
            self.isStrict = try row.get("strict")
            
            self.isUserDefined = (!name.hasPrefix("sqlite_") && schema == "main")
        }
    }
    
    public struct Column: Sendable, InitializableFromResultRow
    {
        public let columnId: Int32
        public let name: String
        public let storageClass: StorageClass
        public let positionInPrimaryKey: Int32?
        public let isNullable: Bool
        public let defaultValue: String?
        public let collation: String?
        
        public init(db: Database, row: Database.Row) throws
        {
            // See https://sqlite.org/pragma.html#pragma_table_info
            /* Columns in the (SQLite) result set include:
             - "name": its name
             - "type": data type if given, else ''
             - "notnull": whether or not the column can be NULL
             - "dflt_value": the default value for the column
             - "pk": either zero for columns that are not part of the primary key, or the 1-based index of the column within the primary key
             */
            
            self.columnId = try row.get("cid")
            self.name = try row.get("name")
            
            let typeString: String = try row.get("type")
            
            // Parse collation from type string (e.g., "TEXT COLLATE NOCASE")
            let typeComponents = typeString.split(separator: " ", maxSplits: 2).map(String.init)
            let storageClassString = typeComponents.first ?? ""
            
            self.storageClass = StorageClass(rawValue: storageClassString) ?? .undefined
            self.collation = nil // not provided by PRAGMA table_info
            
            self.isNullable = try row.get("notnull")
            self.defaultValue = try row.get("dflt_value")
            self.positionInPrimaryKey = try row.get("pk")
        }

        private init(
            columnId: Int32,
            name: String,
            storageClass: StorageClass,
            positionInPrimaryKey: Int32?,
            isNullable: Bool,
            defaultValue: String?,
            collation: String?
        ) {
            self.columnId = columnId
            self.name = name
            self.storageClass = storageClass
            self.positionInPrimaryKey = positionInPrimaryKey
            self.isNullable = isNullable
            self.defaultValue = defaultValue
            self.collation = collation
        }

        func withCollation(_ collation: String?) -> Column
        {
            Column(
                columnId: self.columnId,
                name: self.name,
                storageClass: self.storageClass,
                positionInPrimaryKey: self.positionInPrimaryKey,
                isNullable: self.isNullable,
                defaultValue: self.defaultValue,
                collation: collation
            )
        }
    }
    
    public struct Index: Sendable, InitializableFromResultRow
    {
        public enum Origin: String, Sendable, Storable {
            case createIndex = "c"
            case uniqueConstraint = "u"
            case primaryKeyConstraint = "pk"
            case unknown
        }
        
        public let sequence: Int32
        public let name: String
        public let isUnique: Bool
        public let origin: Origin
        public let isPartial: Bool
        public let columns: [String]
        
        public init(db: Database, row: Database.Row) throws
        {
            // See https://sqlite.org/pragma.html#pragma_index_list
            /* Output columns from the index_list pragma are as follows:
             
             - A sequence number assigned to each index for internal tracking purposes.
             - The name of the index.
             - "1" if the index is UNIQUE and "0" if not.
             - "c" if the index was created by a CREATE INDEX statement, "u" if the index was created by a UNIQUE constraint, or "pk" if the index was created by a PRIMARY KEY constraint.
             - "1" if the index is a partial index and "0" if not.
             */
            
            self.sequence = try row.get("seq")
            self.name = try row.get("name")
            self.isUnique = try row.get("unique")
            self.origin = try row.get("origin")
            self.isPartial = try row.get("partial")
            self.columns = []
        }
        
        init(copying index: Index, columns: [String])
        {
            self.sequence = index.sequence
            self.name = index.name
            self.isUnique = index.isUnique
            self.origin = index.origin
            self.isPartial = index.isPartial
            self.columns = columns
        }
        
        func withColumns(_ columns: [IndexColumn]) -> Self
        {
            Index(copying: self, columns: columns.compactMap({ $0.name }))
        }
    }
    
    public struct IndexColumn: Sendable, InitializableFromResultRow
    {
        public let sequence: Int32
        public let columnId: Int32
        public let name: String?

        public init(db: Database, row: Database.Row) throws
        {
            // See https://sqlite.org/pragma.html#pragma_index_info
            /* Output columns from the index_info pragma are as follows:

             - The rank of the column within the index. (0 means left-most.)
             - The rank of the column within the table being indexed. A value of -1 means rowid and a value of -2 means that an expression is being used.
             - The name of the column being indexed. This columns is NULL if the column is the rowid or an expression.
            */
            
            self.sequence = try row.get("seqno")
            self.columnId = try row.get("cid")
            self.name = try row.get("name")
        }
    }
}
