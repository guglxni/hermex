import SwiftUI
import HermexWatchRoot

struct WatchRootView: View {
    let model: WatchRootModel

    var body: some View {
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
            }
        }
        .padding()
    }
}
