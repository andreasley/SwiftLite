import Foundation

nonisolated public final class ReadAssociatedData: @unchecked Sendable
{
    enum Error: Swift.Error {
        case notFound
        case recursionDetected
    }

    @TaskLocal static var current: ReadAssociatedData?

    let db: Database
    let isolation: (any Actor)?
    var caches: [TypeKey: CacheForType] = [:]
    var fetchedIds = Set<TypedID>()

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
    
    func checkForRecursion<T: Fetchable>(_ type: T.Type, id: UUID) throws
    {
        let typedID = TypedID(type: type, id: id)
        guard !fetchedIds.contains(typedID) else {
            throw Error.recursionDetected
        }
        fetchedIds.insert(typedID)
    }
    
    func printStatistics()
    {
        print("Statistics for last read:")
        for (type, cache) in caches {
            print("\(type.name) has \(cache.objects.count) cached objects")
        }
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
        let typeIdentifier = TypeKey(T.self)
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

extension ReadAssociatedData
{
    struct TypeKey: Hashable, CustomStringConvertible
    {
        let id: ObjectIdentifier
        let name: String
        
        init<T>(_ type: T.Type) {
            self.id = ObjectIdentifier(type)
            self.name = String(reflecting: type)
        }
        
        var description: String { name }
        
        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.id == rhs.id
        }
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }
    
    struct TypedID: Hashable
    {
        let typeKey: TypeKey
        let id: UUID
        
        init<T>(type: T.Type, id: UUID) {
            self.typeKey = TypeKey(type)
            self.id = id
        }
        
        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.typeKey == rhs.typeKey && lhs.id == rhs.id
        }
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(typeKey)
            hasher.combine(id)
        }
    }
}
