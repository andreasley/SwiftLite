# AsyncLoadingView Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                        YOUR SOURCE CODE                              │
│                                                                      │
│  @AsyncLoadingView<DefaultStatusView>                               │
│  struct CarDetailView: View {                                       │
│      @EditableObject(autosaving: true) var car: Car                 │
│      @EditableObject(autosaving: false) var engine: Engine          │
│                                                                      │
│      var body: some View {                                          │
│          Form {                                                     │
│              TextField("Car", text: $car.name)                      │
│              TextField("Engine", text: $engine.name)                │
│          }                                                          │
│      }                                                              │
│  }                                                                  │
└─────────────────────────────────────────────────────────────────────┘
                              ↓
                    ┌─────────────────┐
                    │  Macro Expansion │
                    └─────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────┐
│                      GENERATED EXTENSION                             │
│                                                                      │
│  @MainActor                                                         │
│  extension CarDetailView {                                          │
│      typealias PreloadViewStatusView = DefaultStatusView            │
│                                                                      │
│      ┌──────────────────────────────────────────────────────┐      │
│      │ @Observable                                           │      │
│      │ class ItemsContainer: LoadableItemsContainer {       │      │
│      │     let __reference_car: DatabaseObjectReference<Car>│      │
│      │     private(set) var car: Car?                       │      │
│      │     let __reference_engine: DatabaseObjectReference  │      │
│      │     private(set) var engine: Engine?                 │      │
│      │                                                       │      │
│      │     func load() async throws {                       │      │
│      │         car = try await __reference_car.resolve()    │      │
│      │         engine = try await __reference_engine.resolve()     │
│      │     }                                                 │      │
│      │                                                       │      │
│      │     func save() async throws {                       │      │
│      │         try await car?.save()                        │      │
│      │         try await engine?.save()                     │      │
│      │     }                                                 │      │
│      │                                                       │      │
│      │     func unload() { car = nil; engine = nil }       │      │
│      │                                                       │      │
│      │     var anyItemHasPendingChanges: Bool { ... }      │      │
│      │     var anyItemHasBeenDeleted: Bool { ... }         │      │
│      │ }                                                     │      │
│      └──────────────────────────────────────────────────────┘      │
│                                                                      │
│      ┌──────────────────────────────────────────────────────┐      │
│      │ static func loading(                                 │      │
│      │     car: any DatabaseObjectReferenceConvertible,     │      │
│      │     engine: any DatabaseObjectReferenceConvertible   │      │
│      │ ) -> PreloadView {                                   │      │
│      │     let items = ItemsContainer(                      │      │
│      │         __reference_car: car.getObjectReference(),   │      │
│      │         __reference_engine: engine.getObjectReference()    │
│      │     )                                                 │      │
│      │     return PreloadView(items: items)                 │      │
│      │ }                                                     │      │
│      └──────────────────────────────────────────────────────┘      │
│                                                                      │
│      ┌──────────────────────────────────────────────────────┐      │
│      │ struct PreloadView: View {                           │      │
│      │     @State var items: ItemsContainer                 │      │
│      │                                                       │      │
│      │     var body: some View {                            │      │
│      │         if items.anyItemHasBeenDeleted {             │      │
│      │             ContentUnavailableView(...)              │      │
│      │         } else if let car = items.car,               │      │
│      │                   let engine = items.engine {        │      │
│      │             CarDetailView(                            │      │
│      │                 car: .init(wrappedValue: car, ...),  │      │
│      │                 engine: .init(wrappedValue: engine...)│      │
│      │             )                                         │      │
│      │         }                                             │      │
│      │         .handleModelLifecycle(items, DefaultStatusView)    │
│      │     }                                                 │      │
│      │ }                                                     │      │
│      └──────────────────────────────────────────────────────┘      │
│  }                                                                  │
└─────────────────────────────────────────────────────────────────────┘


                        RUNTIME FLOW DIAGRAM

┌──────────────────────────────────────────────────────────────────────┐
│                                                                       │
│  User Code: CarDetailView.loading(car: carRef, engine: engineRef)   │
│                                                                       │
└──────────────────────┬───────────────────────────────────────────────┘
                       ↓
┌──────────────────────────────────────────────────────────────────────┐
│  loading() creates ItemsContainer with references                    │
│  Returns PreloadView(items: container)                               │
└──────────────────────┬───────────────────────────────────────────────┘
                       ↓
┌──────────────────────────────────────────────────────────────────────┐
│  PreloadView.body renders                                            │
│  Applies .handleModelLifecycle modifier                              │
└──────────────────────┬───────────────────────────────────────────────┘
                       ↓
┌──────────────────────────────────────────────────────────────────────┐
│  ModelLifecycleHandler.onAppear                                      │
│  ├─ Sets status to .loading                                          │
│  ├─ Calls items.load()                                               │
│  │  ├─ Resolves car reference → Car object                           │
│  │  └─ Resolves engine reference → Engine object                     │
│  └─ Sets status to .loaded                                           │
└──────────────────────┬───────────────────────────────────────────────┘
                       ↓
┌──────────────────────────────────────────────────────────────────────┐
│  PreloadView.body renders again                                      │
│  ├─ items.car and items.engine now available                         │
│  ├─ Creates CarDetailView with EditableObject wrappers               │
│  └─ User sees and interacts with the view                            │
└──────────────────────┬───────────────────────────────────────────────┘
                       ↓
┌──────────────────────────────────────────────────────────────────────┐
│  User edits car.name                                                 │
│  ├─ EditableObject updates the model                                 │
│  ├─ items.anyItemHasPendingChanges becomes true                      │
│  └─ Status changes to .unsaved                                       │
└──────────────────────┬───────────────────────────────────────────────┘
                       ↓
┌──────────────────────────────────────────────────────────────────────┐
│  View disappears (user navigates away)                               │
│  ├─ ModelLifecycleHandler.onDisappear triggered                      │
│  ├─ Sets status to .saving                                           │
│  ├─ Calls items.save()                                               │
│  │  ├─ Saves car (autosaving: true)                                  │
│  │  └─ Skips engine if no changes                                    │
│  ├─ Calls items.unload()                                             │
│  │  ├─ Sets car = nil                                                │
│  │  └─ Sets engine = nil                                             │
│  └─ Memory released                                                  │
└──────────────────────────────────────────────────────────────────────┘


                    COMPONENT RELATIONSHIP DIAGRAM

┌────────────────────────────────────────────────────────────────────┐
│                        SwiftUI View Layer                          │
│                                                                    │
│  ┌─────────────────┐      ┌──────────────────────────────┐       │
│  │  CarDetailView  │◄─────│  PreloadView                 │       │
│  │  (Your code)    │      │  (Generated)                 │       │
│  │                 │      │                              │       │
│  │  @EditableObject│      │  @State var items            │       │
│  │  var car        │      │                              │       │
│  └─────────────────┘      └────────────┬─────────────────┘       │
│         ▲                               │                         │
│         │ Created by                    │ Observes                │
│         │                               ▼                         │
│         │                  ┌────────────────────────────┐         │
│         │                  │  ItemsContainer            │         │
│         │                  │  (Generated, @Observable)  │         │
│         │                  │                            │         │
│         │                  │  - __reference_car         │         │
│         └──────────────────│  - car: Car?               │         │
│                            │                            │         │
│                            │  + load()                  │         │
│                            │  + save()                  │         │
│                            │  + unload()                │         │
│                            └────────────┬───────────────┘         │
└─────────────────────────────────────────┼──────────────────────────┘
                                          │
                                          │ Uses
                                          ▼
┌────────────────────────────────────────────────────────────────────┐
│                     Database & Model Layer                         │
│                                                                    │
│  ┌───────────────────┐         ┌──────────────────────────┐      │
│  │ DatabaseObject    │◄────────│  Car (Model)             │      │
│  │ Reference<Car>    │         │                          │      │
│  │                   │         │  var name: String        │      │
│  │  + resolve()      │         │  var price: Double       │      │
│  └───────────────────┘         │                          │      │
│                                │  + save()                │      │
│                                └──────────────────────────┘      │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
                                          ▲
                                          │ Persists to
                                          ▼
┌────────────────────────────────────────────────────────────────────┐
│                          Database                                  │
│                                                                    │
│  ┌──────────────────────────────────────────────────────┐         │
│  │  Database                                             │         │
│  │                                                       │         │
│  │  + get<T>(_ type: T.Type, id: T.ID) async -> T?     │         │
│  │  + save<T>(_ model: T) async throws                 │         │
│  └──────────────────────────────────────────────────────┘         │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘


                        MACRO PROCESSING FLOW

┌─────────────────────────────────────────────────────────────────────┐
│                     Source Code (Input)                              │
│                                                                      │
│  @AsyncLoadingView<DefaultStatusView>                               │
│  struct CarDetailView: View { ... }                                 │
└──────────────────────────┬───────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────────────┐
│                  Swift Compiler Plugin                               │
│                  SwiftLiteMacrosPlugin                               │
│                                                                      │
│  providingMacros: [AsyncLoadingViewMacro.self, ...]                 │
└──────────────────────────┬───────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────────────┐
│              AsyncLoadingViewMacro.expansion()                       │
│                                                                      │
│  1. Validate: Is it a struct?                                       │
│  2. Extract: StatusView type from <DefaultStatusView>               │
│  3. Analyze: Find all @EditableObject properties                    │
│     ├─ Property: car, Type: Car, Autosaving: true                   │
│     └─ Property: engine, Type: Engine, Autosaving: false            │
│  4. Generate:                                                       │
│     ├─ ItemsContainer class                                         │
│     ├─ loading() static method                                      │
│     └─ PreloadView struct                                           │
│  5. Return: ExtensionDeclSyntax                                     │
└──────────────────────────┬───────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────────────┐
│                  Expanded Code (Output)                              │
│                                                                      │
│  struct CarDetailView: View { ... }                                 │
│                                                                      │
│  @MainActor                                                         │
│  extension CarDetailView {                                          │
│      class ItemsContainer { ... }                                   │
│      static func loading(...) -> PreloadView { ... }                │
│      struct PreloadView: View { ... }                               │
│  }                                                                  │
└──────────────────────────┬───────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────────────┐
│                    Compiled Binary                                   │
└─────────────────────────────────────────────────────────────────────┘


                    STATE TRANSITION DIAGRAM

                    ┌─────────┐
                    │ initial │
                    └────┬────┘
                         │
                    onAppear
                         │
                         ▼
                    ┌─────────┐
              ┌─────│ loading │◄────┐
              │     └────┬────┘     │
              │          │           │
        Error │     Success         │ Retry
              │          │           │
              │          ▼           │
              │     ┌────────┐       │
              └────►│ loaded │───────┘
                    └────┬───┘
                         │
                    User edits
                         │
                         ▼
                    ┌─────────┐
              ┌─────│ unsaved │
              │     └────┬────┘
              │          │
     Auto-save│   onDisappear/onChange
     triggers │          │
              │          ▼
              │     ┌────────┐
              └────►│ saving │
                    └────┬───┘
                         │
                    Complete
                         │
                         ▼
                    ┌────────┐
                    │ loaded │
                    └────┬───┘
                         │
                   onDisappear
                         │
                         ▼
                    ┌─────────┐
                    │ unload  │
                    └─────────┘


                DATA FLOW DURING LOAD

User navigates to view
        │
        ▼
CarDetailView.loading(car: ref1, engine: ref2)
        │
        ├─► Creates ItemsContainer(ref1, ref2)
        │
        ├─► Returns PreloadView(items: container)
        │
        ▼
PreloadView renders
        │
        ├─► Applies .handleModelLifecycle
        │
        ▼
ModelLifecycleHandler.onAppear
        │
        ├─► Status: .loading
        │   └─► StatusView shows ProgressView
        │
        ├─► container.load()
        │   │
        │   ├─► ref1.resolve() → Database.get(Car.self, id: ...)
        │   │   └─► Returns Car object
        │   │
        │   ├─► ref2.resolve() → Database.get(Engine.self, id: ...)
        │   │   └─► Returns Engine object
        │   │
        │   └─► Sets container.car and container.engine
        │
        ├─► Status: .loaded
        │   └─► StatusView shows nothing
        │
        ▼
PreloadView.body re-renders
        │
        ├─► Unwraps: let car = items.car, let engine = items.engine
        │
        ├─► Creates: CarDetailView(
        │              car: EditableObject(wrappedValue: car, autosaving: true),
        │              engine: EditableObject(wrappedValue: engine, autosaving: false)
        │            )
        │
        ▼
User sees fully loaded view


                DATA FLOW DURING SAVE

User edits car.name
        │
        ├─► EditableObject's Binding updates car.name
        │
        ├─► car._hasPendingChanges = true
        │
        ├─► container.anyItemHasPendingChanges = true
        │
        ├─► Status: .unsaved
        │   └─► StatusView shows "Unsaved Changes"
        │
        ▼
User navigates away (or app backgrounds)
        │
        ├─► ModelLifecycleHandler.onDisappear
        │
        ├─► Status: .saving
        │   └─► StatusView shows "Saving..."
        │
        ├─► container.save()
        │   │
        │   ├─► car.save() (autosaving: true)
        │   │   └─► Database persists car
        │   │
        │   └─► engine.save() skipped if no changes
        │
        ├─► container.unload()
        │   ├─► car = nil
        │   └─► engine = nil
        │
        ├─► Status: .loaded
        │
        ▼
Memory freed, view dismissed
```

This diagram illustrates:
1. How source code is transformed by the macro
2. Runtime flow from loading to saving
3. Component relationships
4. Macro processing steps
5. State transitions
6. Data flow during load and save operations
