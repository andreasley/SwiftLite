import Observation

@MainActor
public protocol Autosaving: AnyObject, WithTrackedChanges
{
    func _beginAutosaving()
}

@MainActor
public extension Autosaving
{
    func _beginAutosaving() {}
}

@MainActor
public protocol AutosavingModel: AnyObject, Autosaving
{
    var _metadata: ModelMetadata { get }
    nonisolated(nonsending) func save() async throws
}

@MainActor
public extension AutosavingModel
{
    // TODO: Should there be a way to stop autosaving?

    // To be called on the topmost object of an object hierarchy when autosaving is to be enabled for the while graph.
    // This works by tracking changes throughout the whole graph and autosaves after the specified amount of time.
    func _beginAutosaving(delayBeforeSaving: Duration)
    {
        print("_beginAutosaving")
        guard !_metadata.isAutosaving else { return }
        _metadata.isAutosaving = true
        
        // TODO: Using unsafe here can actually load to a crash. Find a better solution.
        nonisolated(unsafe) weak let unsafeSelf = self

        withObservationTracking {
            _ = self._hasPendingChanges
        } onChange: {
            Task { @MainActor in
                guard let unsafeSelf else { return }
                unsafeSelf._metadata.isAutosaving = false
                unsafeSelf._beginAutosaving(delayBeforeSaving: delayBeforeSaving)
                if unsafeSelf._hasPendingChanges {
                    unsafeSelf._scheduleAutosave(delayBeforeSaving: delayBeforeSaving)
                }
            }
        }
    }
    
    func _scheduleAutosave(delayBeforeSaving: Duration)
    {
        self._metadata.autosaveTask?.cancel()
        self._metadata.autosaveTask = Task { [weak self] in
            defer { self?._metadata.autosaveTask = nil }
            try? await Task.sleep(for: delayBeforeSaving)
            guard !Task.isCancelled else { return }
            try? await self?.save()
        }
    }
}
