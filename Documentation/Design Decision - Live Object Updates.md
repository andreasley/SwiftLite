# Question: How to implement live object updates?

- Editable objects can theoretically be updated whenever something in the database changes.

- When showing database objects in SwiftUI (both editable and snapshots), live updates are mandatory.

- When using editable objects without an UI (e.g. server-side), live updates aren't desirable.

- Since usage in SwiftUI is enabled by the respective Property Wrappers, it would be possible to make them subscribe to change notifications from the database. However, this would make it pretty complicated to track changes to nested objects. Also, SwiftUI views (and therefore their properties) may be recreated anytime, so they're not a good place to store a notification token.

- The only way is therefore to store the reference to the object somewhere or let the object itself register/deregister for value change notifications.

- When using SwiftUI, a user may swap out a nested object with another (and would expect the newly inserted one to autoupdate as well).

- When enabling autoupdating too late after initialization, there'd need to be a mechanism to bring the object up to speed when enabling it (full refresh? checksum and updating individual fields? rather complex).

- Enabling autoupdating right in the initializer isn't possible because the object may not be created on the MainActor (even if it'll be living there later)

- Enabling Autoupdating for all objects on the @MainActor should work well for SwiftUI, since only the editable objects can receive update notifications, and they can't be transferred into or out of the actor.

- Options:
	- Enable autoupdating for all objects (unsuitable for server-side)
	- Enable autoupdating for objects on the @MainActor (acceptable as long as SwiftUI always uses MainActor and server-side code never does)
	- Enable autoupdating manually for individual objects (insufficient for SwiftUI)
	- Enable autoupdating with SwiftUI property wrappers (complicated to implement)
	- Enable autoupdating globally per `Database` (acceptable)

**Decisions:**

Automatically enable autoupdating for objects on the @MainActor in an object graph right before it from `Database`. This seems to be the only site where the objects are guaranteed to be on the MainActor (if the caller was, too). 

Additionally, enable autoupdating when saving new objects on the @MainActor.

Subscribe to database change notifications from within the objects and store a notification token in the objects' `Metadata`.

Use a per-actor associated storage as a fan-out proxy that notifies all wrappers that registered for notifications for a specific collection or object ID.

