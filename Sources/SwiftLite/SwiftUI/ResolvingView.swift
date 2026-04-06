import SwiftUI

public struct ResolvingView<S, Content>: View where Content: View, S: ModelSnapshot
{
    let snapshot: S
    @ViewBuilder let content: (S.Model) -> Content
    
    @State private var model: S.Model?
    @State private var error: Error?
    
    public init(snapshot: S, content: @escaping (S.Model) -> Content)
    {
        self.snapshot = snapshot
        self.content = content
    }
    
    public var body: some View {
        Group {
            if let model {
                content(model)
            } else if let error {
                ContentUnavailableView("Object not found", systemImage: "nosign", description: Text(error.localizedDescription))
            } else {
                ProgressView()
            }
        }
        .task {
            if model == nil {
                do {
                    self.model = try await snapshot.getObjectReference().resolve()
                } catch {
                    self.error = error
                }
            }
        }
    }
}
