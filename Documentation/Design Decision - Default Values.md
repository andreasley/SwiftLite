# Question: How to implement default values?

- Default values for persisted properties are a must-have.

- Default values can be tricky, like related objects that require a reference to `Database` and potentially additional parameters for initialization.

- Default values could be implemented in Swift on the model level or set on the SQLite schema (or both).

- SQLite default values are pretty limited compared to what Swift allows.

- As long as all database entries are added through SwiftLite and the default value configurations honored, it's irrelevant if there are any default values set in SQLite - except for migrations, where a previously optional property could theoretically be changed to a non-optional one with a default value (if that will be allowed). In this case, the default value would have to be added by SwiftLite for every respective value that is migrated.

- If no default values have to be provided to SQLite, they don't have to be known by the macro and could instead be provided by a custom initializer - except for the migration mentioned above.

**Decisions:**

Support default values in Swift only. It's complicated enough as it is.

Default values have to be specified in the property's annotation. They are picked up by the macro.

Initializers for related objects have to be called by user-written code (e.g. in a custom initializer).
