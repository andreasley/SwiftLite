# Question: Are model property types required to be `Sendable`?

- Stored values of model properties need to be transferred across isolation domains (e.g. from the `Database` actor to the actor where they're used, like `MainActor` in SwiftUI).

- The values in SQLite are all sendable (basic strings, numbers and `Data`).

- Conversion of raw database data can always occur in the target isolation domain, I think.

- The model class itself isn't sendable.

**Decisions:**

- Model properties don't have to be of a `Sendable` type.

- When saving, values are converted (in the caller's domain) to the data types that SQLite can store and then transferred to the `Database` actor.

