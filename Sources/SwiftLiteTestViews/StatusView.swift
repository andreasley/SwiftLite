import SwiftUI
import SwiftLite

public struct StatusView: View
{
    @Environment(Database.self) private var db
    @State private var status: Database.Status?
    
    public init() {}
    
    public var body: some View {
        VStack {
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
                }
                Spacer()
                if let pendingRemoteChanges = status?.syncStatus.pendingRemoteChanges, pendingRemoteChanges > 0 {
                    Label("\(pendingRemoteChanges)", systemImage: "arrow.down.circle")
                }
            }
            if let progress = status?.syncStatus.currentSyncProgress {
                ProgressView(value: progress.fractionCompleted, total: 1)
                    .progressViewStyle(.linear)
            }
            if let transportStatus = status?.syncStatus.transportStatus {
                switch transportStatus {
                case .connecting:
                    Label("Connecting", systemImage: "circle.dotted")
                case .offline:
                    Label("Offline", systemImage: "network.slash")
                case .error:
                    Label("Error", systemImage: "xmark.octagon.fill")
                case .transferring:
                    Label("Syncing", systemImage: "arrow.trianglehead.2.clockwise.rotate.90.icloud")
                case .connected:
                    Label("Connected", systemImage: "network")
                }
            }
        }
        .frame(maxWidth: 400, alignment: .leading)
        .padding(20)
        .task {
            for await newStatus in await db.statusUpdates.stream() {
                status = newStatus
            }
        }
    }
}
