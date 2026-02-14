# Question: What should the API for related models look like?

- There are different model result types (classes for editable objects and read-only structs; possibly more later).

- As per this library's concept, database values are cached in stored properties of models (so no lazy fetching of values when properties are accessed).

- Related models should be gettable/settable by property.

- Swift currently doesn't support async setters, so related models have to be loaded at the same time as the "parent" – either as editable or read-only.

- If deciding to load all related models as editable: When saving a model, the whole tree of referenced models needs to be saved, too.

- If deciding to load all related models as read-only: There needs to be a Fix-It to ensure the library consumer properly declares the related type as `RelatedType.Snapshot`.

- Note: The read-only models won't be observable.

- Would it be important to be able to set a property with any variant of a model? Or is just calling `.editable()` on the related model simple enough?

- It's possible to later add a feature allowing custom fetching trees (e.g. fetching relations two levels deep) by passing appropriate instructions to the Macro.

- A `PropertyWrapper` could be used to allow setting any variant of a related model. However, there won't be a non-async way to convert from an editable model to a snapshot (and vice versa), so the action couldn't be propagated to the regular property. Additionally, there's the question of when/how the editable-to-read-only model would be saved (because it's actor-isolated and couldn't be referenced by the sendable `Snapshot`).

**Best option:**

- Regular (non-throwing, non-async) getter/setter (can revisit when lazy setter is available)
- Let API consumer decide if related model is to be referenced as editable or non-editable (by choosing the appropriate type, e.g. `RelatedType` or `RelatedType.Snapshot`).
- On saving a model, also save all editable related models.
