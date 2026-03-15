# SwiftLite

SwiftLite is an ORM that provides an easy-to-use Swift API to create and access a SQLite database.
It leverages Swift Macros to transform the model code to a partial database schema on compile-time.

### Implemented Features

- Automatic creation of tables
- Easy to persist custom objects and datatypes 

### Pending features 

- Automatic migration
- Custom queries
- Full Text Search
- Custom migrations (with support for renaming tables and columns etc.)

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

- Support every function of SQLite

### Strategies

- Use type-safe ways whenever possible
- Do as much as possible in the macros




## Limitations

- SwiftLite expects SQLite files to have a specific schema (UUID primary keys for example). Files created by other SQLite-based libraries may or may not be compatible.
- Stored `Decimal` values are clamped to 922'337'203'685'477 and four decimal places.
- Stored `Date` values are limited to millisecond precision.
- Manually entered values in the SQLite file may be clamped if they don't match the schema (e.g. a value of `Int64.max` in an `INTEGER` column that is mapped to a property of type `Int32`).

## Random thoughts

Sometimes (very rarely), Swift features align so beautifully that it's almost magical. This was the case here. I'm grateful for the experience and would like to thank everyone who made this possible.
