#if canImport(SwiftUI)
import SwiftUI

public protocol StatusView: View
{
    init(status: LoadingStatus, items: LoadableItemsContainer)
    static var contentSafeAreaPadding: EdgeInsets { get }
}

#endif
