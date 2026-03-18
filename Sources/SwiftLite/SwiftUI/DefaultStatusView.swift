#if canImport(SwiftUI)
import SwiftUI

public struct DefaultStatusView: View, StatusView
{
    public static var contentSafeAreaPadding: EdgeInsets = EdgeInsets(top: 40, leading: 0, bottom: 0, trailing: 0)
    
    let status: LoadingStatus
    let items: LoadableItemsContainer
    
    @State private var showErrorDetails: Bool = false
    
    public init(status: LoadingStatus, items: LoadableItemsContainer)
    {
        self.status = status
        self.items = items
    }
    
    public var body: some View
    {
        HStack {
            switch status {
            case .initial, .loaded:
                EmptyView()
            case .loading:
                ProgressView("Loading...")
            case .loadingError:
                Label("Loading failed", systemImage: "exclamationmark.circle")
                    .symbolRenderingMode(.monochrome)
                Button {
                    Task {
                        try await items.load()
                    }
                } label: {
                    Image(systemName: "arrow.trianglehead.counterclockwise")
                }
                Button {
                    showErrorDetails = true
                } label: {
                    Image(systemName: "info.circle.fill")
                }
            case .unsaved:
                Label("Unsaved Changes", systemImage: "pencil")
                Button("Save") {
                    Task {
                        try await items.save()
                    }
                }
            case .saving:
                ProgressView("Saving...")
            case .savingError:
                Label("Saving failed", systemImage: "exclamationmark.circle")
                    .symbolRenderingMode(.multicolor)
                Button {
                    Task {
                        try await items.save()
                    }
                } label: {
                    Image(systemName: "arrow.trianglehead.counterclockwise")
                }
                Button {
                    showErrorDetails = true
                } label: {
                    Image(systemName: "info.circle.fill")
                }
            }
        }
        .padding(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10))
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(status.isError ? .red : (status.isWorking ? .white : .systemBlue)))
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                .opacity(status.isIdle ? 0 : 1)
        )
        .transition(.opacity)
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(isPresented: $showErrorDetails) {
            ErrorSheet(status: status)
        }
    }
    
    struct ErrorSheet: View
    {
        @Environment(\.dismiss) private var dismiss

        let title: String
        let errorText: String
        
        init(status: LoadingStatus)
        {
            switch status
            {
            case .loadingError(let error):
                self.title = "Error while loading"
                self.errorText = error.localizedDescription
            case .savingError(let error):
                self.title = "Error while saving"
                self.errorText = error.localizedDescription
            default:
                self.title = "No error"
                self.errorText = "No error detected"
            }
        }
        
        var body: some View {
            NavigationStack {
                Text(errorText)
                    .navigationTitle(title)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                dismiss()
                            }
                        }
                    }
                    .padding(20)
            }
        }
    }
}
#endif
