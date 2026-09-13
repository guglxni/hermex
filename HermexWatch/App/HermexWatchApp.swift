import SwiftUI
import HermexWatchRoot

@main
struct HermexWatchApp: App {
    @State private var model = WatchRootModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchRootView(model: model, screenshotPage: Self.screenshotPage)
                .onAppear {
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("HERMEX_WATCH_SCREENSHOT_FIXTURE") {
                        model.applyScreenshotFixture()
                        WatchWidgetSnapshotPublisher.publish(model)
                        return
                    }
                    #endif
                    wireReachability()
                    WatchSessionActivator.shared.activate()
                    model.attach(link: WatchConnectivitySessionLink())
                    WatchWidgetSnapshotPublisher.publish(model)
                }
                .onChange(of: scenePhase) { _, phase in
                    // Returning to the foreground reloads the registry so an
                    // iPhone active-server switch while the watch was
                    // backgrounded is followed, and a quiet phone is surfaced
                    // honestly instead of showing a stale ready surface.
                    guard phase == .active else { return }
                    model.refreshConnection()
                    WatchWidgetSnapshotPublisher.publish(model)
                }
        }
    }

    /// Wires WCSession activation/reachability callbacks to the model so a
    /// reconnect (after backgrounding, or a quiet phone waking up) refreshes
    /// the wrist. The watch never talks to hermes-webui here — it only asks the
    /// model to re-attach its WatchConnectivity link.
    private func wireReachability() {
        WatchSessionActivator.shared.reachabilityChanged = { reachable in
            Task { @MainActor in
                if reachable {
                    model.handleCompanionReachable()
                } else {
                    model.handleCompanionUnreachable()
                }
                WatchWidgetSnapshotPublisher.publish(model)
            }
        }
    }

    private static var screenshotPage: WatchScreenshotPage {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.arguments
            .first(where: { $0.hasPrefix("HERMEX_WATCH_SCREENSHOT_PAGE=") })?
            .split(separator: "=").last
        {
            return WatchScreenshotPage(rawValue: String(raw)) ?? .now
        }
        #endif
        return .now
    }
}
