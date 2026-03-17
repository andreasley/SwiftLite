#if canImport(SwiftUI)
import SwiftUI

public struct DefaultStatusView: View, StatusView
{
    public static var contentSafeAreaPadding: EdgeInsets = EdgeInsets(top: 40, leading: 0, bottom: 0, trailing: 0)

    let status: LoadingStatus
    let items: LoadableItemsContainer
        
    public init(status: LoadingStatus, items: LoadableItemsContainer)
    {
        self.status = status
        self.items = items
    }
    
    public var body: some View
    {
        Group {
            switch status {
            case .initial:
                EmptyView()
            case .loading:
                ProgressView("Loading...")
                    .padding(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10))
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(.white))
                            .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                    )
            case .loaded:
                EmptyView()
            case .error(let error):
                Label("Error", systemImage: "exclamationmark.circle.fill")
                    .symbolRenderingMode(.multicolor)
                    .padding(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10))
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(.red))
                            .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                    )
            case .unsaved:
                Label("Unsaved Changes", systemImage: "pencil")
                    .padding(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10))
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(.systemBlue))
                            .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                    )
            case .saving:
                ProgressView("Saving...")
                    .padding(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10))
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(.white))
                            .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                    )
            }
        }
        .transition(.opacity)
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
#endif
