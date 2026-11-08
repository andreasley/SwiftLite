#if canImport(SwiftUI)
import SwiftUI

public struct ModelLifecycleHandler<S: StatusView>: ViewModifier
{
    @Environment(\.scenePhase) private var scenePhase
    @State private var status: LoadingStatus = .initial
    @State private var loadingTask: Task<Void, Never>?

    // Created once in `onAppear`. Do NOT give this a default value or create it in `init`: the modifier struct is
    // rebuilt on every body evaluation of its parent, and every throwaway instance would unload the live items
    // from its `deinit`.
    @State private var discardObserver: DiscardObserver?

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
            if discardObserver == nil {
                let items = self.items
                discardObserver = DiscardObserver {
                    items.unload()
                }
            }
            startLoadingIfNeeded()
        }
        .onDisappear {
            // `onDisappear` also fires when the view is merely covered (e.g. by a `fullScreenCover` or a pushed view)
            // and will reappear later. Unloading here would tear down the content – and with it any presentation it
            // owns. So only save here; unloading is handled by `DiscardObserver` once the view's identity is actually
            // removed from the hierarchy.
            startSavingAll()
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
    
    func startLoadingIfNeeded()
    {
        guard loadingTask == nil else { return }

        // The view reappears after having been covered; its items are still loaded then.
        // Only (re)load if nothing has been loaded yet or if the previous attempt failed.
        switch status {
        case .initial, .loadingError:
            break
        default:
            return
        }

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
}

/// Lives in the `@State` storage of `ModelLifecycleHandler`.
///
/// SwiftUI only releases that storage when the view's identity is removed from the hierarchy – not when the view is
/// merely covered – which makes `deinit` a reliable "the view is really gone" signal, unlike `onDisappear`.
private final class DiscardObserver: Sendable
{
    private let onDiscard: @MainActor () -> Void

    init(onDiscard: @escaping @MainActor () -> Void)
    {
        self.onDiscard = onDiscard
    }

    deinit
    {
        let onDiscard = self.onDiscard
        Task { @MainActor in
            onDiscard()
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


