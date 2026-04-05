import Foundation

public enum LoadingStatus: Equatable {
    case initial
    case loading
    case loadingError(Swift.Error)
    case loaded
    case unsaved
    case saving
    case savingError(Swift.Error)
    
    var error: Swift.Error? {
        switch self {
        case .loadingError(let error), .savingError(let error):
            return error
        default:
            return nil
        }
    }

    var isIdle: Bool {
        switch self {
        case .initial, .loaded:
            return true
        default:
            return false
        }
    }

    var isError: Bool {
        switch self {
        case .loadingError, .savingError:
            return true
        default:
            return false
        }
    }
    
    var isWorking: Bool {
        switch self {
        case .loading, .saving:
            return true
        default:
            return false
        }
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.initial, .initial),
             (.loading, .loading),
             (.loaded, .loaded):
            return true
        case (.savingError(let lhsError), .savingError(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        case (.loadingError(let lhsError), .loadingError(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }
}
