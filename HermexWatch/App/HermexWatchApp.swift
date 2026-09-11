import SwiftUI
import HermexWatchRoot

@main
struct HermexWatchApp: App {
    @State private var model = WatchRootModel()

    var body: some Scene {
        WindowGroup {
            WatchRootView(model: model)
        }
    }
}
