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
    
    func _beginAutosaving()
    {
        guard !_metadata.isAutosaving else { return }
        _metadata.isAutosaving = true
        
        nonisolated(unsafe) weak let unsafeSelf = self

        withObservationTracking {
            _ = self._hasPendingChanges
        } onChange: {
            Task { @MainActor in
                guard let unsafeSelf else { return }
                unsafeSelf._metadata.isAutosaving = false
                unsafeSelf._beginAutosaving()
                if unsafeSelf._hasPendingChanges {
                    unsafeSelf._scheduleAutosave()
                }
            }
        }
    }
    
    func _scheduleAutosave()
    {
        self._metadata.autosaveTask?.cancel()
        self._metadata.autosaveTask = Task { [weak self] in
            defer { self?._metadata.autosaveTask = nil }
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            try? await self?.save()
        }
    }
}
