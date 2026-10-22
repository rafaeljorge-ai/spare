import SpareCore
import SwiftUI

/// What the user may do with a scanned item right now.
enum ItemAvailability: Equatable {
    case ready
    case inUse(by: String)
    /// The running processes could not be listed, so nothing proves the item is free.
    case notVerified

    init(_ item: ScanItem) {
        switch item.inUseBy {
        case nil: self = .ready
        case InUseGuard.unknownReason?: self = .notVerified
        case let name?: self = .inUse(by: name)
        }
    }

    /// Items in use and not verified ones are never selectable.
    var isSelectable: Bool { self == .ready }
}

extension ScanItem {
    var availability: ItemAvailability { ItemAvailability(self) }
}
