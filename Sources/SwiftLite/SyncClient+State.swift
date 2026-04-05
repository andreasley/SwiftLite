import SQLite3
import Foundation

extension SyncClient
{
    struct PersistedConfiguration
    {
        let table: ConfigurationTable
        
        var didSuccessfullySyncSometime: Bool {
            get throws {
                let previousServerDatabaseId = try getServerDatabaseId()
                let lastSuccessfulSyncDate = try getLastSuccessfulSyncDate()
                return previousServerDatabaseId != nil && lastSuccessfulSyncDate != nil
            }
        }
        
        init(tableName: String, connectionHandle: OpaquePointer?)
        {
            self.table = ConfigurationTable(tableName: tableName, connectionHandle: connectionHandle)
        }

        func setDefaultValues() throws
        {
            let creationTimestamp = Date().timeIntervalSince1970
            let clientDatabaseId = UUID.v7()
            
            try table.setValue(key: "highest_synchronized_index", value: .int(0))
            try table.setValue(key: "server_database_id", value: .null)
            try table.setValue(key: "client_database_id", value: .string(clientDatabaseId.uuidString))
            try table.setValue(key: "last_successful_sync", value: .null)
            try table.setValue(key: "creation_timestamp", value: .double(creationTimestamp))
            
            print("📝 Initialized SyncClient persisted configuration with client ID: \(clientDatabaseId.uuidString)")
        }

        func getClientDatabaseId() throws -> UUID?
        {
            try table.getValue(key: "client_database_id")
        }
        
        func getServerDatabaseId() throws -> UUID?
        {
            try table.getValue(key: "server_database_id")
        }
        
        public func getHighestSynchronizedIndex() throws -> Int64
        {
            try table.getValue(key: "highest_synchronized_index") ?? 0
        }

        public func getLastSuccessfulSyncDate() throws -> Date?
        {
            try table.getValue(key: "last_successful_sync")
        }

        public func getCreationTimestamp() throws -> Date?
        {
            try table.getValue(key: "creation_timestamp")
        }

        func setServerDatabaseId(_ id: UUID) throws
        {
            try table.setValue(key: "server_database_id", value: .string(id.uuidString))
        }
        
        public func setHighestSynchronizedIndex(_ index: Int64) throws
        {
            try table.setValue(key: "highest_synchronized_index", value: .int(index))
        }
        
        public func setLastSuccessfulSync(_ date: Date = Date.now) throws
        {
            try table.setValue(key: "last_successful_sync", value: .double(date.timeIntervalSince1970))
        }
    }
}
