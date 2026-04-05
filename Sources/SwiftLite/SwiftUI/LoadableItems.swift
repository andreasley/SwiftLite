@MainActor
public protocol LoadableItemsContainer: AnyObject
{
    func load() async throws
    func save() async throws
    func unload()
    
    var anyItemHasPendingChanges: Bool { get }
    var anyItemHasBeenDeleted: Bool { get }
}
