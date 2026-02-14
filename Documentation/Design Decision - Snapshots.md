# Question: How to implement Snapshots (read-only results)?

- In most use-cases, values from the database are just read and passed around (not changed/saved).

- Using read-only structures simplifies working with this data, especially with Swift async/await.

**Decisions:**

- In SwiftLite, these read-only results are called "Model Snapshots" (shortened to just "Snapshot"; not to be confused with "Database Snapshot")

- Snapshots can only be created by `Database` to ensure that they reference an actual object in a database (and aren't created from a non-saved, editable `@Model` class)

- Query functions should by default return snapshots

- Snapshots are to be `Sendable`

- Snapshots should reference `Database` to be able to fetch its related objects async (on demand) in a future release

- Snapshots need to be marked `nonisolated` to ensure they're not isolated by default. The reason for that is that "App" targets in Xcode with Swift 6/Approachable Concurrency has `SWIFT_DEFAULT_ACTOR_ISOLATION` set to `MainActor` by default.