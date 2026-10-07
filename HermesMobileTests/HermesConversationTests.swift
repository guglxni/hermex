import XCTest
import Observation
@testable import HermesMobile

/// `HermesConversation` on targets other than Bot Chat, over #901's socket-level host:
/// a stored session attaches by its key, a new session is created once, and each target
/// keeps its own draft and recent transcript. Bot Chat itself is `BotConversationTests`.
@MainActor final class HermesConversationTests: XCTestCase {
    /// A stored session resumes its own key with no title lookup, and its frames reach the
    /// owner in order: the replay, then the snapshot, then frames that landed meanwhile.
    func testASessionAttachesByItsKeyAndHandsOverOrderedFrames() async {
        let host = runningTurn()
        let (conversation, owner, _) = attach(host, .session(profile: profile, key: "tip"))
        await conversation.activate()
        XCTAssertEqual(conversation.connectionState, .connected)
        XCTAssertEqual(host.requests.compactMap { $0["method"].text }, ["session.resume", "session.events.since", "session.resume"],
                       "no session.list: only a Bot Chat is looked up by title")
        XCTAssertEqual(host.requests.first?["params"]["session_id"].text, "tip")
        XCTAssertEqual(host.transcriptReads(since: 0), [false, true])
        XCTAssertEqual(owner.log, ["root tip", "replay 1", "replay 2", "replay 3", "snapshot", "connected"])

        // Seq 4 and 5 were missed while away; 6 lands live ahead of the replay reply,
        // behind a copy of 4.
        let missed = [frame(4), frame(5)]
        host.next("session.events.since", .init(result: BotFixtureWire.replay(latest: 5, events: missed),
                                                before: [missed[0], frame(6)]))
        owner.log = []
        await conversation.activate()
        XCTAssertFalse(conversation.replayWasReset)
        XCTAssertEqual(owner.log, ["root tip", "replay 4", "replay 5", "snapshot", "frame 6", "connected"])
        conversation.suspend()
    }

    /// A hole in the live stream, or a frame without a `seq`, is the rebuild signal.
    func testASessionSignalsARebuildOnAGap() async {
        let host = runningTurn()
        let (conversation, owner, client) = attach(host, .session(profile: profile, key: "tip"))
        await conversation.activate()
        owner.log = []
        client.onEvent?(frame(4))
        client.onEvent?(frame(4))
        client.onEvent?(frame(7))
        client.onEvent?(.object(["session_id": .string("other-runtime"), "seq": .number(8), "type": .string("message.delta")]))
        client.onEvent?(.object(["session_id": .string("runtime"), "type": .string("message.delta")]))
        XCTAssertEqual(owner.log, ["frame 4", "frame 7 after a gap", "lost frames"],
                       "a repeat and another runtime's frame are dropped")
        XCTAssertEqual(conversation.sequence, 7)
        conversation.suspend()
    }

    /// `session.create` mints the session once; its reduced resume reply (no `session_key`,
    /// no `running`) is accepted, and the stored key comes from `stored_session_id`. A drop
    /// reattaches to that session and only reads.
    func testANewSessionIsCreatedOnceAndAcceptsTheReducedReply() async {
        let host = BotSocketHost()
        let reduced = BotJSON.object([
            "session_id": .string("runtime"), "stored_session_id": .string("fresh"), "message_count": .number(0),
            "messages": .array([]), "info": .object(["profile_name": .string(profile)])
        ])
        host.always("session.create", .init(result: reduced))
        host.always("session.resume", .init(result: reduced))
        host.always("session.events.since", .init(result: BotFixtureWire.replay(latest: 0)))
        let (conversation, owner, client) = attach(host, .new(profile: profile), reconnectDelay: { _ in })
        await conversation.activate()
        XCTAssertEqual(conversation.connectionState, .connected)
        XCTAssertEqual(conversation.target, .session(profile: profile, key: "fresh"))
        XCTAssertEqual(conversation.storedKey, "fresh")
        XCTAssertEqual(host.requests.first?["method"].text, "session.create")
        XCTAssertEqual(host.requests.first?["params"], .object(["profile": .string(profile)]),
                       "no Bot Chat title, and not hidden")
        XCTAssertEqual(host.requests.dropFirst().compactMap { $0["params"]["session_id"].text }, ["fresh", "runtime", "fresh"])
        XCTAssertEqual(owner.log, ["root fresh", "snapshot", "connected"])

        let leaving = host.requests.count
        client.onDisconnect?(BotFailure.transport)
        let reconnected = expectation(description: "reattached after the drop")
        withObservationTracking { _ = conversation.isReconnecting } onChange: { reconnected.fulfill() }
        await fulfillment(of: [reconnected], timeout: 3)
        XCTAssertEqual(conversation.connectionState, .connected)
        XCTAssertEqual(host.requests.dropFirst(leaving).compactMap { $0["method"].text },
                       ["session.resume", "session.events.since", "session.resume"],
                       "no second session.create, and no write of any kind")
        XCTAssertEqual(host.requests.dropFirst(leaving).first?["params"]["session_id"].text, "fresh")
        conversation.suspend()
    }

    /// Bot Chat keeps the keys it always had. Every other target has its own draft, which
    /// survives a relaunch and leaves with its connection, and its own recent transcript.
    func testEachTargetKeepsItsOwnDraftAndRecentTranscript() async throws {
        let server = URL(string: "https://hermes.example")!, connectionID = UUID()
        let chat = ConversationTarget.canonicalChat(profile: profile)
        let session = ConversationTarget.session(profile: profile, key: "tip")
        let targets = [chat, session, .session(profile: profile, key: "other"), .new(profile: profile)]
        XCTAssertEqual(chat.draftKey(server: server, connectionID: connectionID),
                       .bot(server: server, connectionID: connectionID, profile: profile))
        XCTAssertEqual(chat.recentKey(server: server, connectionID: connectionID),
                       .bot(server: server, connectionID: connectionID, profile: profile))

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let drafts = ChatDraftStore(persistence: ChatDraftFilePersistence(directoryURL: directory), debounceDuration: .seconds(60))
        for (index, target) in targets.enumerated() {
            drafts.setDraft("draft \(index)", for: target.draftKey(server: server, connectionID: connectionID))
        }
        try await drafts.flush()
        let restored = await ChatDraftFilePersistence(directoryURL: directory).load()
        XCTAssertEqual(restored.count, targets.count)
        for (index, target) in targets.enumerated() {
            XCTAssertEqual(restored[target.draftKey(server: server, connectionID: connectionID)]?.text, "draft \(index)")
        }
        await drafts.discardBotDrafts(server: server, connectionID: connectionID)
        try await drafts.flush()
        let afterRemoval = await ChatDraftFilePersistence(directoryURL: directory).load()
        XCTAssertTrue(afterRemoval.isEmpty, "a removed connection takes its session drafts too")

        let recent = BotRecentTranscripts()
        XCTAssertNil(ConversationTarget.new(profile: profile).recentKey(server: server, connectionID: connectionID),
                     "a session not created yet has no transcript to keep")
        for (index, target) in targets.dropLast().enumerated() {
            guard let key = target.recentKey(server: server, connectionID: connectionID) else { return XCTFail("\(target)") }
            let message = ChatMessage(role: "assistant", content: "reply \(index)", timestamp: nil, messageId: "row-\(index)")
            recent.save(.bot(.init(root: "root \(index)", messages: [message], activity: [])), for: key, owner: recent.begin(key))
        }
        for (index, target) in targets.dropLast().enumerated() {
            guard let key = target.recentKey(server: server, connectionID: connectionID),
                  case .bot(let saved)? = recent.snapshot(for: key) else { return XCTFail("\(target)") }
            XCTAssertEqual(saved.root, "root \(index)")
        }
    }

    private let profile = "inbox-triage"

    /// A host whose replay holds the running turn through seq 3.
    private func runningTurn() -> BotSocketHost {
        let host = BotSocketHost()
        host.always("session.events.since", .init(result: BotFixtureWire.replay(latest: 3, events: [frame(1), frame(2), frame(3)])))
        return host
    }

    /// An engine on `target` over a fresh connection to `host`, with an owner that logs.
    private func attach(_ host: BotSocketHost, _ target: ConversationTarget,
                        reconnectDelay: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) })
        -> (HermesConversation, RecordingOwner, BotClient) {
        addTeardownBlock { HermesHostFixture.reset() }
        let record = BotConnection(id: UUID(), name: "Mac", address: URL(string: "http://hermes.local:9120")!,
                                   username: "user", password: "fixture")
        let client = BotClient(http: host.connection(record))
        let conversation = HermesConversation(server: URL(string: "https://hermes.example")!, connection: record,
                                              target: target, wire: client, reconnectDelay: reconnectDelay)
        let owner = RecordingOwner()
        conversation.owner = owner
        return (conversation, owner, client)
    }

    private func frame(_ seq: Int) -> BotJSON {
        .object(["session_id": .string("runtime"), "seq": .number(Double(seq)), "type": .string("message.delta"),
                 "payload": .object(["text": .string("part \(seq)")])])
    }
}

/// Logs what the engine hands over, in order.
@MainActor private final class RecordingOwner: HermesConversationOwner {
    var log: [String] = []

    func conversationDidReset() {}
    func conversationDidIdentify(root: String) { log.append("root \(root)") }
    func conversationDidReplay(_ reply: BotJSON, frames: [BotJSON]) {
        log += frames.map { "replay \($0["seq"].integer ?? 0)" }
    }
    func conversationDidReadSnapshot(_ snapshot: BotJSON, runtime: String, attempt: Int) async throws { log.append("snapshot") }
    func conversationDidConnect(runtime: String, attempt: Int) async throws { log.append("connected") }
    func conversation(didReceive frame: BotJSON, afterGap: Bool) {
        log.append("frame \(frame["seq"].integer ?? 0)" + (afterGap ? " after a gap" : ""))
    }
    func conversationDidLoseFrames() { log.append("lost frames") }
    func conversationDidDisconnect(_ failure: BotFailure, retrying: Bool) {}
}
