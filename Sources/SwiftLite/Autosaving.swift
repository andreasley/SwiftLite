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

        Task {
            for await _ in observe(\._hasPendingChanges) {
                self._metadata.isAutosaving = false
                if self._hasPendingChanges {
                    self._scheduleAutosave(delayBeforeSaving: delayBeforeSaving)
                }
            }
        }
    }

    func _scheduleAutosave(delayBeforeSaving: Duration)
    {
        _metadata.nextAutosave = .now.advanced(by: delayBeforeSaving)
        
        guard self._metadata.autosaveTask == nil else { return }
        self._metadata.autosaveTask = Task { [weak self] in
            defer { self?._metadata.autosaveTask = nil }
            guard let nextAutosave = self?._metadata.nextAutosave else { return }
            while nextAutosave > .now {
                try? await Task.sleep(until: nextAutosave, tolerance: .seconds(1))
            }
            try? await self?.save()
        }
    }
}

public extension AutosavingModel
{
    func observe<Value: Sendable>(_ keyPath: KeyPath<Self, Value>) -> AsyncStream<Value>
    {
        nonisolated(unsafe) weak let unsafeObject = self
        nonisolated(unsafe) let unsafeKeyPath = keyPath
        nonisolated(unsafe) var trackOnce: (@MainActor () -> Void)?

        return AsyncStream { continuation in
            Task { @MainActor in
                guard unsafeObject != nil else {
                    continuation.finish()
                    return
                }

                trackOnce = {
                    guard let observedObject = unsafeObject else {
                        continuation.finish()
                        return
                    }

                    withObservationTracking {
                        _ = observedObject[keyPath: unsafeKeyPath]
                    } onChange: {
                        Task { @MainActor in
                            guard let value = unsafeObject else {
                                continuation.finish()
                                return
                            }
                            continuation.yield(value[keyPath: unsafeKeyPath])
                            trackOnce?()
                        }
                    }
                }

                trackOnce?()
            }
        }
    }

}
