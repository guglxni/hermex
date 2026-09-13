import Foundation
import Testing
@testable import WatchShared

@Suite struct WatchTranscriptProjectionTests {
    @Test func splitsCodeFencesImagesAndStripsAttachedFiles() {
        let message = WatchPhoneMessageHint(
            id: "m1",
            role: .assistant,
            text: """
            Intro
            ```swift
            print("hi")
            ```
            ![shot](/tmp/workspace/shot.png)
            See MEDIA:other.jpg later

            [Attached files: /tmp/workspace/clip.m4a]
            """,
            attachments: [
                WatchPhoneAttachmentHint(name: "clip.m4a", path: "/tmp/workspace/clip.m4a", mime: "audio/m4a", isImage: false),
                WatchPhoneAttachmentHint(name: "extra.png", path: "/tmp/workspace/extra.png", mime: "image/png", isImage: true),
            ]
        )

        let blocks = WatchTranscriptProjection.blocks(for: message)
        #expect(blocks.contains(where: { if case .text(let role, let text) = $0.kind { return role == .assistant && text.contains("Intro") } else { return false } }))
        #expect(blocks.contains(where: { if case .code(let language, let text, false) = $0.kind { return language == "swift" && text.contains("print") } else { return false } }))
        #expect(blocks.contains(where: { if case .image(let path, _, let alt) = $0.kind { return path == "/tmp/workspace/shot.png" && alt == "shot" } else { return false } }))
        #expect(blocks.contains(where: { if case .image(let path, _, _) = $0.kind { return path == "other.jpg" } else { return false } }))
        #expect(blocks.contains(where: { if case .unsupported("audio", let summary) = $0.kind { return summary == "clip.m4a" } else { return false } }))
        #expect(blocks.contains(where: { if case .image(let path, _, _) = $0.kind { return path == "/tmp/workspace/extra.png" } else { return false } }))
        #expect(blocks.contains(where: { if case .text(_, let text) = $0.kind { return text.contains("[Attached files:") } else { return false } }) == false)
    }

    @Test func toolResultIsASingleToolRow() {
        let message = WatchPhoneMessageHint(
            id: "t1",
            role: .user,
            text: String(repeating: "x", count: 400),
            tools: [WatchPhoneToolHint(title: "bash", state: "done", summary: nil)],
            isToolResult: true
        )
        let blocks = WatchTranscriptProjection.blocks(for: message)
        #expect(blocks.count == 1)
        guard case .tool(let title, let state, let summary) = blocks[0].kind else {
            Issue.record("expected a tool block")
            return
        }
        #expect(title == "bash")
        #expect(state == "done")
        #expect((summary?.count ?? 0) <= WatchTranscriptProjection.maximumToolSummaryCharacters)
        #expect(summary?.hasSuffix("…") == true)
    }

    @Test func assistantToolCallsPrecedeText() {
        let message = WatchPhoneMessageHint(
            id: "a1",
            role: .assistant,
            text: "Done.",
            tools: [WatchPhoneToolHint(title: "read", state: "called", summary: "README.md")]
        )
        let blocks = WatchTranscriptProjection.blocks(for: message)
        #expect(blocks.count == 2)
        guard case .tool(let title, let state, let summary) = blocks[0].kind else {
            Issue.record("expected a tool block first")
            return
        }
        #expect(title == "read")
        #expect(state == "called")
        #expect(summary == "README.md")
        guard case .text(let role, let text) = blocks[1].kind else {
            Issue.record("expected assistant text")
            return
        }
        #expect(role == .assistant)
        #expect(text == "Done.")
    }

    @Test func synthesizedPhotoCaptionMatchesIOSComposer() {
        let uploaded = WatchChatAttachment(
            name: "watch-photo.jpg",
            path: "/tmp/workspace/watch-photo.jpg",
            mime: "image/jpeg",
            size: 12,
            isImage: true
        )
        #expect(
            WatchTranscriptProjection.chatMessageText(draft: "", attachments: [uploaded])
            == "I've uploaded 1 file(s): /tmp/workspace/watch-photo.jpg"
        )
        #expect(
            WatchTranscriptProjection.chatMessageText(draft: "look", attachments: [uploaded])
            == "look\n\n[Attached files: /tmp/workspace/watch-photo.jpg]"
        )
    }

    @Test func truncatesLongCode() {
        let message = WatchPhoneMessageHint(
            id: "c1",
            role: .assistant,
            text: "```\n\(String(repeating: "a", count: 2_000))\n```"
        )
        let blocks = WatchTranscriptProjection.blocks(for: message)
        guard case .code(_, let text, true) = blocks[0].kind else {
            Issue.record("expected truncated code")
            return
        }
        #expect(text.count <= WatchTranscriptProjection.maximumCodeCharacters)
        #expect(text.hasSuffix("…"))
    }
}
