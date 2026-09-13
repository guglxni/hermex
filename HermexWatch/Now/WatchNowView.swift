import SwiftUI
import HermexWatchRoot
import WatchShared

struct WatchNowView: View {
    @Bindable var model: WatchRootModel
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @State private var speaker = WatchReplySpeaker()
    @State private var isCreating = false

    var body: some View {
        Group {
            if let session = model.nowSession {
                sessionBody(session)
            } else {
                emptyBody
            }
        }
        .navigationTitle("Now")
    }

    private var emptyBody: some View {
        VStack(spacing: 8) {
            Text(model.primaryMessage)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("No session")
                .font(.headline)
            Text("Create one, or open Sessions.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let error = model.errorCopy {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            Button {
                Task { await createSession() }
            } label: {
                if isCreating { ProgressView() } else { Text("New session") }
            }
            .disabled(isCreating || !model.canMutate)
            NavigationLink {
                WatchSessionListView(model: model)
            } label: {
                Text("Sessions")
            }
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func sessionBody(_ session: WatchSessionSummary) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(model.primaryMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(session.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(statusLabel(for: session))
                    .font(.caption2)
                    .foregroundStyle(statusColor(for: session))
                if let error = model.errorCopy {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                if !isLuminanceReduced {
                    WatchSpeakControls(
                        model: model,
                        session: session,
                        listenAction: model.nowPreview.map { text in
                            { speaker.toggle(text) }
                        }
                    )
                    if let preview = model.nowPreview {
                        Text(preview)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity)
                    }
                    NavigationLink {
                        WatchSessionDetailView(model: model, session: session)
                    } label: {
                        Text("Open chat")
                    }
                    .frame(maxWidth: .infinity)
                    NavigationLink {
                        WatchSessionListView(model: model)
                    } label: {
                        Text("Sessions")
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 4)
        }
        .accessibilityElement(children: .contain)
    }

    private func statusLabel(for session: WatchSessionSummary) -> String {
        if WatchNowSession.isRunning(session.runState) { return "Running" }
        if WatchNowSession.needsAttention(session) { return "Needs you" }
        if session.isPinned { return "Pinned" }
        return "Ready"
    }

    private func statusColor(for session: WatchSessionSummary) -> Color {
        if WatchNowSession.isRunning(session.runState) { return .orange }
        if WatchNowSession.needsAttention(session) { return .yellow }
        return .secondary
    }

    private func createSession() async {
        isCreating = true
        defer { isCreating = false }
        if await model.createSession() != nil {
            WatchHaptics.play(.success)
            WatchWidgetSnapshotPublisher.publish(model)
        } else {
            WatchHaptics.play(.failure)
        }
    }
}
