import WatchShared
import XCTest
@testable import HermexWatchRoot

final class WatchNowSessionTests: XCTestCase {
    func testPrefersRunningThenAttentionThenPinnedThenRecent() throws {
        let scope = try makeScope()
        let older = try session(scope, id: "old", title: "Older", isPinned: false, updatedAt: Date(timeIntervalSince1970: 10))
        let pinned = try session(scope, id: "pin", title: "Pinned", isPinned: true, updatedAt: Date(timeIntervalSince1970: 5))
        let attention = try session(scope, id: "att", title: "Needs you", attention: true, updatedAt: Date(timeIntervalSince1970: 1))
        let running = try session(scope, id: "run", title: "Running", runState: .thinking, updatedAt: Date(timeIntervalSince1970: 2))

        XCTAssertEqual(WatchNowSession.preferred(from: [older, pinned, attention, running])?.key.sessionID, "run")
        XCTAssertEqual(WatchNowSession.preferred(from: [older, pinned, attention])?.key.sessionID, "att")
        XCTAssertEqual(WatchNowSession.preferred(from: [older, pinned])?.key.sessionID, "pin")
        XCTAssertEqual(WatchNowSession.preferred(from: [older])?.key.sessionID, "old")
    }

    func testWidgetActivityMatchesWristPriority() throws {
        let scope = try makeScope()
        let idle = try session(scope, id: "idle", title: "Idle")
        let attention = try session(scope, id: "att", title: "Wait", attention: true)
        let running = try session(scope, id: "run", title: "Run", runState: .responding)

        XCTAssertEqual(WatchNowSession.widgetActivity(from: []), .unknown)
        XCTAssertEqual(WatchNowSession.widgetActivity(from: [idle]), .idle)
        XCTAssertEqual(WatchNowSession.widgetActivity(from: [idle, attention]), .needsAttention)
        XCTAssertEqual(WatchNowSession.widgetActivity(from: [idle, attention, running]), .running)
    }

    func testLastAssistantPreviewTruncates() {
        let blocks: [WatchTranscriptBlock] = [
            .text(id: "1", role: .user, text: "hello"),
            .text(id: "2", role: .assistant, text: String(repeating: "a", count: 200)),
        ]
        let preview = WatchTranscriptPreview.lastAssistantText(in: blocks, maxCharacters: 20)
        XCTAssertEqual(preview?.count, 20)
        XCTAssertTrue(preview?.hasSuffix("…") == true)
    }

    func testLastAssistantPreviewIgnoresCodeAndToolRows() {
        let blocks: [WatchTranscriptBlock] = [
            .code(id: "c", language: "swift", text: "let x = 1", isTruncated: false),
            .tool(id: "t", title: "read", state: "done", summary: "ok"),
            .text(id: "2", role: .assistant, text: "Ready."),
        ]
        XCTAssertEqual(WatchTranscriptPreview.lastAssistantText(in: blocks), "Ready.")
    }

    private func makeScope() throws -> ServerScope {
        ServerScope(
            epoch: InstallationEpoch(rawValue: UUID()),
            server: ServerID(rawValue: UUID()),
            generation: try Generation(1)
        )
    }

    private func session(
        _ scope: ServerScope,
        id: String,
        title: String,
        attention: Bool = false,
        isPinned: Bool = false,
        runState: WatchRunPhase? = nil,
        updatedAt: Date? = nil
    ) throws -> WatchSessionSummary {
        try WatchSessionSummary(
            key: SessionKey(scope: scope, sessionID: id),
            title: title,
            profile: nil,
            workspaceLabel: nil,
            updatedAt: updatedAt,
            isPinned: isPinned,
            isArchived: false,
            attention: attention,
            runState: runState
        )
    }
}
