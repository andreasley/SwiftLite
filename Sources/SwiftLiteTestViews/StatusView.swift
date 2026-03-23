import SwiftUI
import SwiftLite

struct StatusView: View
{
    @Environment(Database.self) private var db
    @State private var status: Database.Status?
    
    var body: some View {
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
            if let pendingLocalChanges = status?.syncStatus.pendingLocalChanges, pendingLocalChanges > 0 {
                Text("Pending local changes: \(pendingLocalChanges)")
            }
            if let pendingRemoteChanges = status?.syncStatus.pendingRemoteChanges, pendingRemoteChanges > 0 {
                Text("Pending remote changes: \(pendingRemoteChanges)")
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
                    if let progress = status?.syncStatus.currentSyncProgress {
                        ProgressView("Download (\(progress.totalUnitCount)", value: progress.fractionCompleted, total: 1)
                            .progressViewStyle(.linear)
                    }
                case .connected:
                    Label("Connected", systemImage: "network")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .task {
            for await newStatus in db.statusStream {
                status = newStatus
            }
        }
    }
}
