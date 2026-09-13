import SwiftUI
import HermexWatchRoot
import WatchShared

struct WatchSessionDetailView: View {
    @Bindable var model: WatchRootModel
    let session: WatchSessionSummary

    @State private var blocks: [WatchTranscriptBlock] = []
    @State private var speaker = WatchReplySpeaker()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    transcriptRow(block)
                }
                if let error = model.errorCopy {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.leading)
                }
                WatchSpeakControls(
                    model: model,
                    session: session,
                    compact: true,
                    listenAction: WatchTranscriptPreview.lastAssistantText(in: blocks).map { text in
                        { speaker.toggle(text) }
                    }
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(session.title)
        .task {
            model.focus(session)
            blocks = await model.transcript(for: session)
        }
        .onChange(of: model.sessions) { _, _ in
            Task { blocks = await model.transcript(for: session) }
        }
    }

    @ViewBuilder
    private func transcriptRow(_ block: WatchTranscriptBlock) -> some View {
        switch block {
        case .text(_, let role, let text):
            Text(text)
                .font(.footnote)
                .foregroundStyle(role == .user ? .primary : .secondary)
        case .code(_, _, let text, _):
            Text(text)
                .font(.footnote.monospaced())
        case .tool(_, let title, let state, _):
            Text("\(title) · \(state)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .image(_, _, let alt):
            Text(alt ?? "Image")
                .font(.caption2)
        case .unsupported(_, let kind, let summary):
            Text("\(kind): \(summary)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
