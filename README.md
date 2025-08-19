### Limitations

- SwiftLite expects SQLite files to have a specific schema (UUID primary keys for example). Files created by other SQLite-based libraries may or may not be compatible.

### Goals

- Run on all platforms that Swift and SQLite run on
- Well integrated into SwiftUI 
- Easy to use, understand and troubleshoot
- No crashes/fatal errors when used correctly
- As few layers of abstraction as possible between Swift and SQLite
- Fast enough for typical use-cases
- Small and lightweight; as few dependencies as possible

### Non-goals

- Support every function of SQLite