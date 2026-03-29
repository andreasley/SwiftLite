import SwiftUI
import SwiftLite

public struct StatusView: View
{
    @Environment(Database.self) private var db
    @State private var status: Database.Status?
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 12) {
            if case .fatalError(let error) = status?.localStatus {
                Group {
                    Label("Database closed", systemImage: "exclamationmark.octagon.fill")
                        .symbolRenderingMode(.multicolor)
                    Text(error.localizedDescription)
                        .font(.footnote)
                }
                .background(.regularMaterial)
                .padding(20)
            }
            HStack {
                if let pendingLocalChanges = status?.syncStatus.pendingLocalChanges, pendingLocalChanges > 0 {
                    Label("\(pendingLocalChanges)", systemImage: "arrow.up.circle")
                        .frame(maxWidth: 100, alignment: .leading)
                }
                if let pendingRemoteChanges = status?.syncStatus.pendingRemoteChanges, pendingRemoteChanges > 0 {
                    Label("\(pendingRemoteChanges)", systemImage: "arrow.down.circle")
                        .frame(maxWidth: 100, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let progress = status?.syncStatus.currentSyncProgress, progress.fractionCompleted > 0.01 {
                ProgressView(value: progress.fractionCompleted, total: 1)
                    .progressViewStyle(.linear)
            }
            Group {
                if let connectorStatus = status?.syncStatus.connectorStatus {
                    switch connectorStatus {
                    case .connecting:
                        Label("Connecting", systemImage: "circle.dotted")
                    case .offline:
                        Label("Offline", systemImage: "network.slash")
                    case .error:
                        Label("Disconnected", systemImage: "exclamationmark.triangle.fill")
                    case .transferring:
                        Label("Transferring", systemImage: "arrow.trianglehead.2.clockwise.rotate.90.icloud")
                    case .connected:
                        Label("Connected", systemImage: "network")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .symbolRenderingMode(.multicolor)
        }
        .frame(maxWidth: 400, alignment: .leading)
        .padding(20)
    }
}
