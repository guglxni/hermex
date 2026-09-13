import SwiftUI
import UIKit
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
        case .code(_, let language, let text, let isTruncated):
            VStack(alignment: .leading, spacing: 2) {
                if let language, !language.isEmpty {
                    Text(language)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(text)
                    .font(.footnote.monospaced())
                if isTruncated {
                    Text("Truncated — open on iPhone")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(4)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        case .tool(_, let title, let state, let summary):
            VStack(alignment: .leading, spacing: 2) {
                Text("\(title) · \(state)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let summary, !summary.isEmpty {
                    Text(summary)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        case .image(_, let descriptor, let alt):
            WatchTranscriptImageRow(model: model, descriptor: descriptor, alt: alt)
        case .unsupported(_, let kind, let summary):
            Text("\(friendlyKind(kind)): \(summary)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func friendlyKind(_ kind: String) -> String {
        switch kind {
        case "image": return "Image"
        case "audio": return "Audio"
        case "file": return "File"
        default: return kind
        }
    }
}

private struct WatchTranscriptImageRow: View {
    let model: WatchRootModel
    let descriptor: WatchMediaDescriptor
    let alt: String?

    @State private var bytes: Data?

    var body: some View {
        Group {
            if let bytes, let image = UIImage(data: bytes) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .accessibilityLabel(alt ?? "Image")
            } else {
                Text(alt ?? "Image — open on iPhone")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            bytes = await model.mediaBytes(for: descriptor)
        }
    }
}
