import Foundation

nonisolated public final class ReadAssociatedData: @unchecked Sendable
{
    enum Error: Swift.Error {
        case notFound
    }

    @TaskLocal static var current: ReadAssociatedData?

    let db: Database
    let isolation: (any Actor)?
    var caches: [ObjectIdentifier: CacheForType] = [:]
    
    init(db: Database, isolation: isolated (any Actor)? = #isolation)
    {
        self.db = db
        self.isolation = isolation
    }
    
    static func getCurrent() throws -> ReadAssociatedData
    {
        guard let current else { throw Error.notFound }
        return current
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

