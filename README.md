# SwiftLite

SwiftLite is a **prototype** of an ORM that provides an easy-to-use Swift API to create and access a SQLite database.
It leverages Swift Macros to transform the model code to a partial database schema on compile-time.

### Implemented Features

- Automatic creation of tables and automatic schema migration (only additive changes are allowed)
- Easy to persist custom objects and datatypes
- Some parts of querying by predicate
- Field-level sync

### Pending features 

- Full Text Search

## How to use it

#### Models

- Must be `class` and annotated with `@Model`
- Automatically get the property `id`, a random UUID, as the primary key

## Concept

### Goals

- Run on all platforms that Swift and SQLite run on
- Well integrated into SwiftUI 
- Easy to use, understand and troubleshoot
- Optimized for simple use-cases (in both performance and ergonomics)
- No crashes/fatal errors when used correctly
- As few layers of abstraction as possible between Swift and SQLite
- Small and lightweight; as few dependencies as possible

### Non-goals

- SwiftLite won't ever support every function of SQLite.

### Strategies

- Use type-safe ways whenever possible
- Do as much as possible in the macros




## Limitations

- SwiftLite expects SQLite files to have a specific schema (UUID primary keys for example). Files created by other SQLite-based libraries are most likely not compatible.
- `Decimal` values are stored as Int64 with 3 decimal places
- `Date` values are stored witg millisecond precision.
- Manually entered values in the SQLite file may be clamped if they don't match the schema (e.g. a value of `Int64.max` in an `INTEGER` column that is mapped to a property of type `Int32`).

