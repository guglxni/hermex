import SwiftUI
import HermexWatchRoot
import WatchShared

private struct CreatedSession: Hashable, Identifiable {
    let key: SessionKey
    /// Full scope, not just the server: the same session ID can reappear under a
    /// later generation of the same server.
    var id: String {
        let scope = key.scope
        return [
            scope.epoch.rawValue.uuidString,
            scope.server.rawValue.uuidString,
            String(scope.generation.rawValue),
            key.sessionID,
        ].joined(separator: ":")
    }
}

struct WatchSessionListView: View {
    @Bindable var model: WatchRootModel
    @State private var isCreating = false
    @State private var createdSession: CreatedSession?

    var body: some View {
        List {
            Button {
                Task { await createSession() }
            } label: {
                if isCreating {
                    HStack {
                        ProgressView()
                        Text("New session")
                    }
                } else {
                    Label("New session", systemImage: "plus")
                }
            }
            .accessibilityIdentifier("createSession")
            .disabled(isCreating || !model.canMutate)

            if model.sessions.isEmpty {
                Text("No sessions")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.sessions, id: \.key) { session in
                NavigationLink {
                    WatchSessionDetailView(model: model, session: session)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(session.title)
                                .font(.headline)
                            Spacer(minLength: 4)
                            if WatchNowSession.isRunning(session.runState) {
                                Image(systemName: "ellipsis.circle")
                                    .foregroundStyle(.orange)
                                    .accessibilityLabel("Running")
                            } else if WatchNowSession.needsAttention(session) {
                                Image(systemName: "exclamationmark.circle")
                                    .foregroundStyle(.yellow)
                                    .accessibilityLabel("Needs you")
                            } else if session.isPinned {
                                Image(systemName: "pin.fill")
                                    .foregroundStyle(.secondary)
                                    .accessibilityLabel("Pinned")
                            }
                        }
                        if let profile = session.profile {
                            Text(profile)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Sessions")
        .navigationDestination(item: $createdSession) { created in
            if let session = model.session(for: created.key) {
                WatchSessionDetailView(model: model, session: session)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await createSession() }
                } label: {
                    if isCreating {
                        ProgressView()
                    } else {
                        Image(systemName: "plus")
                    }
                }
                .accessibilityLabel("New session")
                .accessibilityIdentifier("createSessionToolbar")
                .disabled(isCreating || !model.canMutate)
            }
        }
        .refreshable {
            await model.refreshFromList()
            WatchWidgetSnapshotPublisher.publish(model)
        }
    }

    private func createSession() async {
        isCreating = true
        defer { isCreating = false }
        guard let key = await model.createSession() else {
            WatchHaptics.play(.failure)
            return
        }
        WatchHaptics.play(.success)
        WatchWidgetSnapshotPublisher.publish(model)
        createdSession = CreatedSession(key: key)
    }
}
