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
            if let pendingLocalChanges = status?.pendingLocalChanges, pendingLocalChanges > 0 {
                Text("Pending local changes: \(pendingLocalChanges)")
            }
            if let syncStatus = status?.syncStatus {
                switch syncStatus {
                case .connecting:
                    Label("Access denied", systemImage: "circle.dotted")
                case .offline:
                    Label("Access denied", systemImage: "network.slash")
                case .accessDenied:
                    Label("Access denied", systemImage: "person.crop.circle.badge.xmark")
                case .syncing(let progress, ):
                    Label("Syncing", systemImage: "arrow.trianglehead.2.clockwise.rotate.90.icloud")
                    ProgressView("Download (\(progress.totalUnitCount)", value: progress.fractionCompleted, total: 1)
                        .progressViewStyle(.linear)
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
