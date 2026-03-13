import SwiftUI

public protocol ModelLifecycleEventTriggeringView<Content>: View
{
    associatedtype Content: View
    
    func loadAll() async throws
    func saveAll() async throws
    func unloadAll()
    
    var content: Content { get }
    var scenePhase: ScenePhase { get }
    var loadingTask: State<Task<Void, Never>?> { get }
}

public extension ModelLifecycleEventTriggeringView
{
    var body: some View {
        Group {
            content
        }
        .onAppear(perform: startLoading)
        .onDisappear {
            startSavingAllAndUnloading()
        }
        .onChange(of: scenePhase) { oldValue, newValue in
            startSavingAll()
        }
        .onSubmit {
            startSavingAll()
        }
#if canImport(AppKit)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignMainNotification)) { _ in
            startSavingAll()
        }
//        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in
//            // this can't be used, because choosing a value in a `Picker` will trigger it
//            startSavingAll()
//        }
//        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
//            // this can't be used, because choosing a value in a `Picker` will trigger it
//            startSavingAll()
//        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            startSavingAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willHideNotification)) { _ in
            startSavingAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            startSavingAll()
        }
#endif
#if canImport(UIKit)
        .onReceive(NotificationCenter.default.publisher(for: UIFocusSystem.didUpdateNotification)) { _ in
            startSavingAll()
        }
#endif
    }
    
    func startLoading()
    {
        guard loadingTask.wrappedValue == nil else { return }
        self.loadingTask.wrappedValue = Task {
            do {
                try await loadAll()
            } catch {
                // TODO: Log errors somewhere
            }
            self.loadingTask.wrappedValue = nil
        }
    }
    
    func startSavingAll()
    {
        // Use `Task.immediate` here, because otherwise the Task will not run when called after receiving `NSApplication.willTerminateNotification`
        Task.immediate {
            do {
                try await saveAll()
            } catch {
                // TODO: Log errors somewhere
            }
        }
    }

    func startSavingAllAndUnloading()
    {
        Task {
            do {
                try await saveAll()
                unloadAll()
            } catch {
                // TODO: Log errors somewhere
            }
        }
    }
}

