## What is it?

SwiftLite is a ORM that provides an easy-to-use Swift API to create and access a SQLite database.
It leverages Swift Macros to prepare SQL statements at compile time - great for performance and transparency.

## Basics

#### Models

- Must be `class` and annotated with `@Model`
- Automatically get the property `id`, a random UUID, as the primary key
- May contain a `static let tableName = "<your_preferred_name>"` to manually specify the table name to be used (instead of one derived from the name of the class) 

## Goals

- Run on all platforms that Swift and SQLite run on
- Well integrated into SwiftUI 
- Easy to use, understand and troubleshoot
- No crashes/fatal errors when used correctly
- As few layers of abstraction as possible between Swift and SQLite
- Fast enough for typical use-cases
- Small and lightweight; as few dependencies as possible

## Non-goals

- Support every function of SQLite


## Pending features 

- Custom queries
- Full Text Search
- Custom migrations (with support for renaming tables and columns etc.)

## Limitations

- SwiftLite expects SQLite files to have a specific schema (UUID primary keys for example). Files created by other SQLite-based libraries may or may not be compatible.
- Stored `Decimal` values are clamped to 922'337'203'685'477 and four decimal places.
- Stored `Date` values are limited to millisecond precision.
- Manually entered values in the SQLite file may be clamped if they don't match the schema (e.g. a value of `Int64.max` in an `INTEGER` column that is mapped to a property of type `Int32`).

## Various

Sometimes (very rarely), Swift features align so beautifully that it's almost magical. This was the case here. I'm grateful for the experience and would like to thank everyone who made this possible.