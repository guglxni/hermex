import SwiftUI
import HermexWatchRoot
import WatchShared

enum WatchScreenshotPage: String {
    case now
    case sessions
    case detail
}

enum WatchChrome: Hashable {
    case sessions
}

struct WatchRootView: View {
    @Bindable var model: WatchRootModel
    var screenshotPage: WatchScreenshotPage = .now
    @State private var path = NavigationPath()

    var body: some View {
        switch model.state {
        case .setupRequired, .connecting, .unavailable, .signedOut:
            connectionState
        case .ready:
            NavigationStack(path: $path) {
                WatchNowView(model: model)
                    .navigationDestination(for: WatchChrome.self) { _ in
                        WatchSessionListView(model: model)
                    }
                    .navigationDestination(for: SessionKey.self) { key in
                        if let session = model.sessions.first(where: { $0.key == key }) {
                            WatchSessionDetailView(model: model, session: session)
                        } else {
                            ProgressView()
                        }
                    }
            }
            .onAppear {
                applyScreenshotPath()
            }
            .onChange(of: model.sessions) { _, _ in
                WatchWidgetSnapshotPublisher.publish(model)
            }
        }
    }

    private func applyScreenshotPath() {
        switch screenshotPage {
        case .now:
            break
        case .sessions:
            path.append(WatchChrome.sessions)
        case .detail:
            if let key = model.nowSession?.key {
                path.append(key)
            }
        }
    }

    private var connectionState: some View {
        VStack(spacing: 8) {
            Text("Hermex")
                .font(.headline)

            switch model.state {
            case .setupRequired:
                Text(model.primaryMessage)
                    .font(.body.weight(.semibold))
                Text("Pairing and server provisioning are not configured yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            case .connecting:
                ProgressView()
                Text("Connecting")
                    .font(.footnote)
            case .unavailable:
                Text("Hermex is unavailable")
                    .font(.body.weight(.semibold))
                Text("Open Hermex on your iPhone to review setup.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            case .signedOut:
                Text("Sign in on iPhone")
                    .font(.body.weight(.semibold))
                Text("Open Hermex on your iPhone and sign in to continue.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            case .ready:
                EmptyView()
            }
        }
        .padding()
    }
}
