import Observation

@MainActor
@Observable
public final class WatchRootModel {
    public private(set) var state: WatchLaunchState

    public init() {
        state = .setupRequired
    }

    public func beginConnecting() {
        state = .connecting
    }

    public func markUnavailable() {
        state = .unavailable
    }

    public var primaryMessage: String {
        switch state {
        case .setupRequired:
            return "Set up on iPhone"
        case .connecting:
            return "Connecting"
        case .unavailable:
            return "Hermex is unavailable"
        }
    }
}
