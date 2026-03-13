import Foundation

public enum LoadingStatus: Equatable {
    case initial
    case loading
    case loaded
    case error(Swift.Error)
    
    var isError: Bool {
        if case .error = self { return true }
        return false
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.initial, .initial),
             (.loading, .loading),
             (.loaded, .loaded):
            return true
        case (.error(let lhsError), .error(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }
}
