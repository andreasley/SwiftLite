public nonisolated protocol WithTrackedChanges: AnyObject
{
    var _hasPendingChanges: Bool { get }
}
