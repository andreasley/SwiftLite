# Question: How to implement autosaving for editable objects?

- For editable objects, changes are logged in the object's metadata. Saving persists these changes to the database.

- When binding editable objects in SwiftUI, value changes should be saved automatically (by default; potentially configurable).

- When using editable objects without an UI (e.g. server-side), autosaving isn't desirable.

- In Swift 6, `nonisolated` objects can't call into themselves with a delay (because there's no isolation domain to guarantee safety; scheduling a Task would require capturing the non-sendable `self`). Therefore, autosaving can't be initiated from within the editable object itself.

- Since usage in SwiftUI is enabled by a Property Wrapper that references a single `Model` and provides the property bindings, this would be the optimal place to detect value changes and queue/debounce an automatic save.


**Decisions:**

Add scheduled autosaving functionality to the `LoadedObject` property wrapper.
Add view lifecycle hooks to a View, e.g. `Preload`.