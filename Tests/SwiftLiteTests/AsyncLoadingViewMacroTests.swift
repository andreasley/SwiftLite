import Testing
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import SwiftLiteMacros

@Suite("AsyncLoadingView Macro Tests")
struct AsyncLoadingViewMacroTests {
    
    let testMacros: [String: Macro.Type] = [
        "AsyncLoadingView": AsyncLoadingViewMacro.self,
    ]
    
    @Test("Generates extension with single EditableObject")
    func singleEditableObject() {
        assertMacroExpansion(
            """
            @AsyncLoadingView(statusView: DefaultStatusView.self)
            struct CarDetailView: View {
                @EditableObject(autosaving: true) var car: Car
                
                var body: some View {
                    Text("Hello")
                }
            }
            """,
            expandedSource: """
            struct CarDetailView: View {
                @EditableObject(autosaving: true) var car: Car
                
                var body: some View {
                    Text("Hello")
                }

                @Observable
                class ItemsContainer: LoadableItemsContainer {
                    let __reference_car: DatabaseObjectReference<Car>
                    private(set) var car: Car?
            
                    init(__reference_car: DatabaseObjectReference<Car>) {
                        self.__reference_car = __reference_car
                    }
            
                    func load() async throws {
                        car = try await __reference_car.resolve()
                    }
                    
                    func save() async throws {
                        try await car?.save()
                    }
                    
                    func unload() {
                        car = nil
                    }
                    
                    var anyItemHasPendingChanges: Bool {
                        let hasChanges = [
                            car?._hasPendingChanges,
                        ]
                        .contains(true)
                        return hasChanges
                    }
            
                    var anyItemHasBeenDeleted: Bool {
                        let hasChanges = [
                            car?.hasBeenDeletedFromDatabase,
                        ]
                        .contains(true)
                        return hasChanges
                    }
                }
            }
            
            @MainActor
            extension CarDetailView {
                typealias PreloadViewStatusView = DefaultStatusView
                
                static func loading(car: any DatabaseObjectReferenceConvertible<Car>) -> PreloadView {
                    let items = ItemsContainer(__reference_car: car.getObjectReference())
                    return PreloadView(items: items)
                }
                
                struct PreloadView: View {
                    @State var items: ItemsContainer
            
                    @ViewBuilder
                    var body: some View {
                        Group {
                            if items.anyItemHasBeenDeleted {
                                ContentUnavailableView("One of the objects in this view has been deleted", systemImage: "trash")
                            } else if let car = items.car {
                                CarDetailView(car: .init(wrappedValue: car, autosaving: true))
                            }
                        }
                        .handleModelLifecycle(items: items, statusView: DefaultStatusView.self)
                    }
                }
            }
            """,
            macros: testMacros
        )
    }
    
    @Test("Generates extension with multiple EditableObjects")
    func multipleEditableObjects() {
        assertMacroExpansion(
            """
            @AsyncLoadingView(statusView: DefaultStatusView.self)
            struct CarEngineView: View {
                @EditableObject(autosaving: true) var car: Car
                @EditableObject(autosaving: false) var engine: Engine
                
                var body: some View {
                    Text("Hello")
                }
            }
            """,
            expandedSource: """
            struct CarEngineView: View {
                @EditableObject(autosaving: true) var car: Car
                @EditableObject(autosaving: false) var engine: Engine
                
                var body: some View {
                    Text("Hello")
                }

                @Observable
                class ItemsContainer: LoadableItemsContainer {
                    let __reference_car: DatabaseObjectReference<Car>
                    private(set) var car: Car?
                    let __reference_engine: DatabaseObjectReference<Engine>
                    private(set) var engine: Engine?
            
                    init(__reference_car: DatabaseObjectReference<Car>, __reference_engine: DatabaseObjectReference<Engine>) {
                        self.__reference_car = __reference_car
                        self.__reference_engine = __reference_engine
                    }
            
                    func load() async throws {
                        car = try await __reference_car.resolve()
                        engine = try await __reference_engine.resolve()
                    }
                    
                    func save() async throws {
                        try await car?.save()
                    }
                    
                    func unload() {
                        car = nil
                        engine = nil
                    }
                    
                    var anyItemHasPendingChanges: Bool {
                        let hasChanges = [
                            car?._hasPendingChanges,
                        ]
                        .contains(true)
                        return hasChanges
                    }
            
                    var anyItemHasBeenDeleted: Bool {
                        let hasChanges = [
                            car?.hasBeenDeletedFromDatabase,
                            engine?.hasBeenDeletedFromDatabase,
                        ]
                        .contains(true)
                        return hasChanges
                    }
                }
            }
            
            @MainActor
            extension CarEngineView {
                typealias PreloadViewStatusView = DefaultStatusView
                
                static func loading(car: any DatabaseObjectReferenceConvertible<Car>, engine: any DatabaseObjectReferenceConvertible<Engine>) -> PreloadView {
                    let items = ItemsContainer(__reference_car: car.getObjectReference(), __reference_engine: engine.getObjectReference())
                    return PreloadView(items: items)
                }
                
                struct PreloadView: View {
                    @State var items: ItemsContainer
            
                    @ViewBuilder
                    var body: some View {
                        Group {
                            if items.anyItemHasBeenDeleted {
                                ContentUnavailableView("One of the objects in this view has been deleted", systemImage: "trash")
                            } else if let car = items.car, let engine = items.engine {
                                CarEngineView(car: .init(wrappedValue: car, autosaving: true), engine: .init(wrappedValue: engine, autosaving: false))
                            }
                        }
                        .handleModelLifecycle(items: items, statusView: DefaultStatusView.self)
                    }
                }
            }
            """,
            macros: testMacros
        )
    }
    
    @Test("Generates extension with custom StatusView")
    func customStatusView() {
        assertMacroExpansion(
            """
            @AsyncLoadingView(statusView: MyCustomStatusView.self)
            struct CarDetailView: View {
                @EditableObject(autosaving: true) var car: Car
                
                var body: some View {
                    Text("Hello")
                }
            }
            """,
            expandedSource: """
            struct CarDetailView: View {
                @EditableObject(autosaving: true) var car: Car
                
                var body: some View {
                    Text("Hello")
                }

                @Observable
                class ItemsContainer: LoadableItemsContainer {
                    let __reference_car: DatabaseObjectReference<Car>
                    private(set) var car: Car?
            
                    init(__reference_car: DatabaseObjectReference<Car>) {
                        self.__reference_car = __reference_car
                    }
            
                    func load() async throws {
                        car = try await __reference_car.resolve()
                    }
                    
                    func save() async throws {
                        try await car?.save()
                    }
                    
                    func unload() {
                        car = nil
                    }
                    
                    var anyItemHasPendingChanges: Bool {
                        let hasChanges = [
                            car?._hasPendingChanges,
                        ]
                        .contains(true)
                        return hasChanges
                    }
            
                    var anyItemHasBeenDeleted: Bool {
                        let hasChanges = [
                            car?.hasBeenDeletedFromDatabase,
                        ]
                        .contains(true)
                        return hasChanges
                    }
                }
            }
            
            @MainActor
            extension CarDetailView {
                typealias PreloadViewStatusView = MyCustomStatusView
                
                static func loading(car: any DatabaseObjectReferenceConvertible<Car>) -> PreloadView {
                    let items = ItemsContainer(__reference_car: car.getObjectReference())
                    return PreloadView(items: items)
                }
                
                struct PreloadView: View {
                    @State var items: ItemsContainer
            
                    @ViewBuilder
                    var body: some View {
                        Group {
                            if items.anyItemHasBeenDeleted {
                                ContentUnavailableView("One of the objects in this view has been deleted", systemImage: "trash")
                            } else if let car = items.car {
                                CarDetailView(car: .init(wrappedValue: car, autosaving: true))
                            }
                        }
                        .handleModelLifecycle(items: items, statusView: MyCustomStatusView.self)
                    }
                }
            }
            """,
            macros: testMacros
        )
    }
    
    @Test("Produces error when no EditableObject properties")
    func noEditableObjectsError() {
        assertMacroExpansion(
            """
            @AsyncLoadingView(statusView: DefaultStatusView.self)
            struct CarDetailView: View {
                @State var name: String = ""
                
                var body: some View {
                    Text("Hello")
                }
            }
            """,
            expandedSource: """
            struct CarDetailView: View {
                @State var name: String = ""
                
                var body: some View {
                    Text("Hello")
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@AsyncLoadingView requires at least one @EditableObject property",
                    line: 1,
                    column: 1,
                    severity: .error
                )
            ],
            macros: testMacros
        )
    }
    
    @Test("Uses DefaultStatusView when no statusView parameter provided")
    func defaultStatusView() {
        assertMacroExpansion(
            """
            @AsyncLoadingView
            struct CarDetailView: View {
                @EditableObject(autosaving: true) var car: Car
                
                var body: some View {
                    Text("Hello")
                }
            }
            """,
            expandedSource: """
            struct CarDetailView: View {
                @EditableObject(autosaving: true) var car: Car
                
                var body: some View {
                    Text("Hello")
                }

                @Observable
                class ItemsContainer: LoadableItemsContainer {
                    let __reference_car: DatabaseObjectReference<Car>
                    private(set) var car: Car?
            
                    init(__reference_car: DatabaseObjectReference<Car>) {
                        self.__reference_car = __reference_car
                    }
            
                    func load() async throws {
                        car = try await __reference_car.resolve()
                    }
                    
                    func save() async throws {
                        try await car?.save()
                    }
                    
                    func unload() {
                        car = nil
                    }
                    
                    var anyItemHasPendingChanges: Bool {
                        let hasChanges = [
                            car?._hasPendingChanges,
                        ]
                        .contains(true)
                        return hasChanges
                    }
            
                    var anyItemHasBeenDeleted: Bool {
                        let hasChanges = [
                            car?.hasBeenDeletedFromDatabase,
                        ]
                        .contains(true)
                        return hasChanges
                    }
                }
            }
            
            @MainActor
            extension CarDetailView {
                typealias PreloadViewStatusView = DefaultStatusView
                
                static func loading(car: any DatabaseObjectReferenceConvertible<Car>) -> PreloadView {
                    let items = ItemsContainer(__reference_car: car.getObjectReference())
                    return PreloadView(items: items)
                }
                
                struct PreloadView: View {
                    @State var items: ItemsContainer
            
                    @ViewBuilder
                    var body: some View {
                        Group {
                            if items.anyItemHasBeenDeleted {
                                ContentUnavailableView("One of the objects in this view has been deleted", systemImage: "trash")
                            } else if let car = items.car {
                                CarDetailView(car: .init(wrappedValue: car, autosaving: true))
                            }
                        }
                        .handleModelLifecycle(items: items, statusView: DefaultStatusView.self)
                    }
                }
            }
            """,
            macros: testMacros
        )
    }
    
    @Test("Ignores non-EditableObject properties")
    func ignoresOtherProperties() {
        assertMacroExpansion(
            """
            @AsyncLoadingView(statusView: DefaultStatusView.self)
            struct CarDetailView: View {
                @EditableObject(autosaving: true) var car: Car
                @State var isEditing: Bool = false
                @Environment(\\.dismiss) var dismiss
                
                var body: some View {
                    Text("Hello")
                }
            }
            """,
            expandedSource: """
            struct CarDetailView: View {
                @EditableObject(autosaving: true) var car: Car
                @State var isEditing: Bool = false
                @Environment(\\.dismiss) var dismiss
                
                var body: some View {
                    Text("Hello")
                }

                @Observable
                class ItemsContainer: LoadableItemsContainer {
                    let __reference_car: DatabaseObjectReference<Car>
                    private(set) var car: Car?
            
                    init(__reference_car: DatabaseObjectReference<Car>) {
                        self.__reference_car = __reference_car
                    }
            
                    func load() async throws {
                        car = try await __reference_car.resolve()
                    }
                    
                    func save() async throws {
                        try await car?.save()
                    }
                    
                    func unload() {
                        car = nil
                    }
                    
                    var anyItemHasPendingChanges: Bool {
                        let hasChanges = [
                            car?._hasPendingChanges,
                        ]
                        .contains(true)
                        return hasChanges
                    }
            
                    var anyItemHasBeenDeleted: Bool {
                        let hasChanges = [
                            car?.hasBeenDeletedFromDatabase,
                        ]
                        .contains(true)
                        return hasChanges
                    }
                }
            }
            
            @MainActor
            extension CarDetailView {
                typealias PreloadViewStatusView = DefaultStatusView
                
                static func loading(car: any DatabaseObjectReferenceConvertible<Car>) -> PreloadView {
                    let items = ItemsContainer(__reference_car: car.getObjectReference())
                    return PreloadView(items: items)
                }
                
                struct PreloadView: View {
                    @State var items: ItemsContainer
            
                    @ViewBuilder
                    var body: some View {
                        Group {
                            if items.anyItemHasBeenDeleted {
                                ContentUnavailableView("One of the objects in this view has been deleted", systemImage: "trash")
                            } else if let car = items.car {
                                CarDetailView(car: .init(wrappedValue: car, autosaving: true))
                            }
                        }
                        .handleModelLifecycle(items: items, statusView: DefaultStatusView.self)
                    }
                }
            }
            """,
            macros: testMacros
        )
    }
    
    @Test("Handles all EditableObjects with autosaving: false")
    func allNonAutosavingObjects() {
        assertMacroExpansion(
            """
            @AsyncLoadingView
            struct EngineDetailView: View {
                @EditableObject(autosaving: false) var engine: Engine
                
                var body: some View {
                    Text("Hello")
                }
            }
            """,
            expandedSource: """
            struct EngineDetailView: View {
                @EditableObject(autosaving: false) var engine: Engine
                
                var body: some View {
                    Text("Hello")
                }

                @Observable
                class ItemsContainer: LoadableItemsContainer {
                    let __reference_engine: DatabaseObjectReference<Engine>
                    private(set) var engine: Engine?
            
                    init(__reference_engine: DatabaseObjectReference<Engine>) {
                        self.__reference_engine = __reference_engine
                    }
            
                    func load() async throws {
                        engine = try await __reference_engine.resolve()
                    }
                    
                    func save() async throws {
                        // No autosaving properties to save
                    }
                    
                    func unload() {
                        engine = nil
                    }
                    
                    var anyItemHasPendingChanges: Bool {
                        return false
                    }
            
                    var anyItemHasBeenDeleted: Bool {
                        let hasChanges = [
                            engine?.hasBeenDeletedFromDatabase,
                        ]
                        .contains(true)
                        return hasChanges
                    }
                }
            }
            
            @MainActor
            extension EngineDetailView {
                typealias PreloadViewStatusView = DefaultStatusView
                
                static func loading(engine: any DatabaseObjectReferenceConvertible<Engine>) -> PreloadView {
                    let items = ItemsContainer(__reference_engine: engine.getObjectReference())
                    return PreloadView(items: items)
                }
                
                struct PreloadView: View {
                    @State var items: ItemsContainer
            
                    @ViewBuilder
                    var body: some View {
                        Group {
                            if items.anyItemHasBeenDeleted {
                                ContentUnavailableView("One of the objects in this view has been deleted", systemImage: "trash")
                            } else if let engine = items.engine {
                                EngineDetailView(engine: .init(wrappedValue: engine, autosaving: false))
                            }
                        }
                        .handleModelLifecycle(items: items, statusView: DefaultStatusView.self)
                    }
                }
            }
            """,
            macros: testMacros
        )
    }
}
