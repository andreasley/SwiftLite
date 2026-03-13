import Foundation

public nonisolated struct DatabaseTask: Sendable
{
    enum Error: Swift.Error {
        case alreadyInTransaction
        case transactionNotFound
    }
    
    @TaskLocal static var currentWriteTransaction: WriteTransaction?
    @TaskLocal static var currentReadTransaction: ReadTransaction?
    
    nonisolated public struct WriteTransaction: Sendable, Equatable, Hashable
    {
        let db: Database
        let id: UUID
        
        public func hash(into hasher: inout Hasher)
        {
            hasher.combine(id)
            hasher.combine(ObjectIdentifier(db))
        }
        
        public static func == (lhs: DatabaseTask.WriteTransaction, rhs: DatabaseTask.WriteTransaction) -> Bool
        {
            lhs.id == rhs.id && ObjectIdentifier(lhs.db) == ObjectIdentifier(rhs.db)
        }
    }
    
    static func getWriteTransaction() throws -> WriteTransaction
    {
        guard let currentWriteTransaction else { throw Error.transactionNotFound }
        return currentWriteTransaction
    }
    
    nonisolated public final class ReadTransaction: @unchecked Sendable
    {
        let db: Database
        let isolation: (any Actor)?
        var caches: [ObjectIdentifier: CacheForType] = [:]
        
        init(db: Database, isolation: isolated (any Actor)? = #isolation)
        {
            self.db = db
            self.isolation = isolation
        }
        
        func getCached<T: Fetchable>(_ type: T.Type, id: UUID) -> T?
        {
            getCacheForType(T.self).getObject(id: id)
        }
        
        func addCached<T: Fetchable>(_ type: T.Type, id: UUID, object: T)
        {
            getCacheForType(T.self).addObject(object)
        }
        
        func getCacheForType<T: Fetchable>(_ type: T.Type = T.self) -> CacheForType
        {
            let typeIdentifier = ObjectIdentifier(T.self)
            if let existingCache = caches[typeIdentifier] {
                return existingCache
            } else {
                let newCache = CacheForType()
                caches[typeIdentifier] = newCache
                return newCache
            }
        }
        
        class CacheForType
        {
            var objects: [UUID: any Fetchable] = [:]
            
            func getObject<T: Fetchable>(id: UUID) -> T?
            {
                objects[id] as? T
            }
            
            func addObject(_ object: any Fetchable)
            {
                objects[object.id] = object
            }
        }
        
    }

}
