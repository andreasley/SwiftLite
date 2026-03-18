#if canImport(SwiftUI)
import SwiftUI

public struct ModelLifecycleHandler<S: StatusView>: ViewModifier
{
    @Environment(\.scenePhase) private var scenePhase
    @State private var status: LoadingStatus = .initial
    @State private var loadingTask: Task<Void, Never>?

    let items: LoadableItemsContainer
        
    public func body(content: Content) -> some View
    {
        ZStack(alignment: .topLeading) {
            content
            S.init(status: status, items: items)
        }
        .onChange(of: items.anyItemHasPendingChanges) { oldValue, newValue in
            guard !status.isError else { return }
            if newValue {
                setStatus(.unsaved)
            } else {
                setStatus(.loaded)
            }
        }
        .onAppear {
            startLoading()
        }
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
    //  .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in
    //      // this can't be used, because choosing a value in a `Picker` will trigger it
    //      startSavingAll()
    //  }
    //  .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
    //      // this can't be used, because choosing a value in a `Picker` will trigger it
    //      startSavingAll()
    //  }
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
    
    func setStatus(_ status: LoadingStatus)
    {
        withAnimation(.easeInOut(duration: 0.2)) {
            self.status = status
        }
    }
    
    func startLoading()
    {
        guard loadingTask == nil else { return }
        self.loadingTask = Task {
            do {
                setStatus(.loading)
                try await items.load()
                setStatus(.loaded)
            } catch {
                setStatus(.loadingError(error))
            }
            self.loadingTask = nil
        }
    }
    
    func startSavingAll()
    {
        guard items.anyItemHasPendingChanges else { return }
        
        // Use `Task.immediate` here, because otherwise the Task will not run when called after receiving `NSApplication.willTerminateNotification`
        Task.immediate {
            do {
                setStatus(.saving)
                try await items.save()
                setStatus(.loaded)
            } catch {
                setStatus(.savingError(error))
            }
        }
    }

    func startSavingAllAndUnloading()
    {
        guard items.anyItemHasPendingChanges else {
            items.unload()
            return
        }

        Task {
            do {
                setStatus(.saving)
                try await items.save()
                setStatus(.loaded)
                items.unload()
            } catch {
                setStatus(.savingError(error))
                // TODO: Escalate this somehow? The view might be hidden now.
            }
        }
    }
}

public extension View
{
    func handleModelLifecycle<S: StatusView>(items: LoadableItemsContainer, statusView: S.Type = DefaultStatusView.self) -> some View {
        modifier(
            ModelLifecycleHandler<S>(items: items)
        )
    }
}



#endif


