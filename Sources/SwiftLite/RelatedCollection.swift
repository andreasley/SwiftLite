import Foundation

// SwiftUI `List` only updates if the collection passed to it is a mutating struct. Classes that conform to `RandomAccessCollection` don't work as expected, even when @Observable or manually calling the observation functions when appropriate. Additionally, we need a way to handle append/remove, because these may trigger additional work to be done, so the struct needs to have corresponding handlers registered. Also, the user shouldn't be able to replace the collection, because that would remove these handlers.
// This struct provides the necessary ergonomics to be used by the various `RelatedX` properties
public nonisolated struct RelatedCollection<Element>: RandomAccessCollection where Element: Fetchable
{
    typealias OnMutateCallback = (Element) -> Void
    typealias OnMoveCallback = (IndexSet, Int) -> Void

    public var startIndex: Int { items.startIndex }
    public var endIndex: Int { items.endIndex }
    
    internal var items: [Element]
    
    internal var onAppend: OnMutateCallback?
    internal var onRemove: OnMutateCallback?
    internal var onMove: OnMoveCallback?

    init(items: [Element] = [])
    {
        self.items = items
    }

    public subscript(index: Int) -> Element
    {
        get { items[index] }
        set { items[index] = newValue }
    }

    public func append(_ element: Element)
    {
        onAppend?(element)
    }
    
    public func remove(_ element: Element)
    {
        onRemove?(element)
    }
    
    public func move(fromOffsets source: IndexSet, toOffset destination: Int)
    {
        onMove?(source, destination)
    }
}

extension RelatedCollection: Equatable
{
    public static func == (lhs: RelatedCollection<Element>, rhs: RelatedCollection<Element>) -> Bool {
        lhs.items == rhs.items
    }
}
