# Question: Should the central `Database` be an actor?

- Access to the database needs to be possible from multiple different threads/actors.

- Channeling all database access through an actor would simplify reasoning about concurrency.

- Using an actor would require all fetching and saving to be async. 

- Some usage of objects will happen in @MainActor, for example  everything related to SwiftUI. If using an actor, synchronous access won't be possible from SwiftUI views. Handling the async loading in these cases will require some preloading mechanism (and probably some status view).

**Decisions:**

In the end, database access requires IO (which may block). Making access async is the proper way to deal with this anyway, so it doesn't make much difference if the central database object is an actor.

An actor's guarantee that all SQLite functions are run in the same isolation domain is definitely a plus, too.

The planned way to serialize data when reading/writing to the database make it easy to transfer data across isolation domains.

`Database` will be an `actor`.