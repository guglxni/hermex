import Foundation
import Testing
@testable import WatchShared

/// Loops a wire message straight into the dispatcher so tests exercise the
/// full encode/validate path in-process without WatchConnectivity.
private final class LoopTransport: WatchWireTransporting, @unchecked Sendable {
    let dispatcher: WatchWireDispatcher
    init(dispatcher: WatchWireDispatcher) { self.dispatcher = dispatcher }
    func send(_ message: WatchWireMessage) async throws -> WatchWireReply {
        await dispatcher.handle(message)
    }
}

@Suite struct WatchWireRoundTripTests {

    @Test func registryAndSendRoundTripThroughTheWire() async throws {
        let backend = ScriptedPhoneBackend()
        let broker = PhoneCompanionBroker(
            epoch: InstallationEpoch(rawValue: UUID()),
            backend: backend,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        // The client validates reply envelopes against the request, including
        // expiry, so its `now` must sit inside the request's validity window
        // (the broker uses a fixed clock; the client must agree with it).
        let now: @Sendable () -> Date = { Date(timeIntervalSince1970: 1_700_000_010) }
        let client = WatchWireClient(transport: LoopTransport(dispatcher: WatchWireDispatcher(service: broker)), now: now)

        let registry = await client.registry()
        #expect(registry.entries.count == 1)
        let scope = try #require(registry.entries.first?.scope)
        let sessions = try await client.refreshSessions(scope: scope, collection: .current, query: nil, localLimit: 10)
        #expect(sessions.value.items.map(\.title) == ["Planning"])

        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let context = try CommandContext(
            stableCommandID: CommandID(rawValue: UUID()),
            scope: scope,
            expectedRevision: registry.revision,
            createdAt: created,
            expiresAt: created.addingTimeInterval(60)
        )
        let receipt = await client.send(text: "go", to: sessions.value.items[0].key, context: context)
        #expect(receipt.receipt.phase == .acknowledged)
        #expect(receipt.value?.streamID == "stream-1")

        let transcribeDispatcher = WatchWireDispatcher(service: broker) { request in
            await broker.sendVoiceNote(request)
        }
        let voiceClient = WatchWireClient(transport: LoopTransport(dispatcher: transcribeDispatcher), now: now)
        let note = try WatchVoiceNoteRequest(
            scope: scope,
            expectedRevision: registry.revision,
            session: try SessionKey(scope: scope, sessionID: "s1"),
            filename: "voice-note-test.m4a",
            audio: Data(repeating: 0x1, count: 32)
        )
        let voiceReceipt = try await voiceClient.sendVoiceNote(note)
        #expect(voiceReceipt.receipt.phase == .acknowledged)
        #expect(voiceReceipt.value?.streamID == "stream-1")
    }
}

private final class ScriptedPhoneBackend: WatchPhoneBackend, @unchecked Sendable {
    func servers() async -> [WatchPhoneServerAccount] {
        [WatchPhoneServerAccount(urlString: "https://alpha.example", displayName: "Alpha")]
    }
    func listSessions(urlString: String, archived: Bool, query: String?, limit: Int) async throws -> [WatchPhoneSessionRow] {
        [
            WatchPhoneSessionRow(
                sessionID: "s1",
                title: "Planning",
                profile: nil,
                workspaceLabel: nil,
                updatedAt: nil,
                isPinned: false,
                isArchived: false,
                attention: false,
                runState: nil
            ),
        ]
    }
    func createSession(urlString: String, profileID: String?, workspace: String?) async throws -> String { "s2" }
    func startChat(urlString: String, sessionID: String, message: String) async throws -> String { "stream-1" }
    func startChat(
        urlString: String,
        sessionID: String,
        message: String,
        attachments: [WatchChatAttachment]?
    ) async throws -> String { "stream-1" }
    func uploadFile(
        urlString: String,
        sessionID: String,
        data: Data,
        filename: String
    ) async throws -> WatchChatAttachment {
        WatchChatAttachment(
            name: filename,
            path: "/tmp/workspace/\(filename)",
            mime: "audio/m4a",
            size: data.count,
            isImage: false
        )
    }
    func cancelChat(urlString: String, streamID: String) async throws {}
    func transcript(urlString: String, sessionID: String, before: Int?, limit: Int) async throws -> WatchPhoneTranscriptPage {
        WatchPhoneTranscriptPage(blocks: [], nextBefore: nil, isTruncated: false)
    }
    func runPhase(urlString: String, sessionID: String, streamID: String) async throws -> (phase: WatchRunPhase, isTerminal: Bool) {
        (.responding, false)
    }
    func transcribeAudio(urlString: String, data: Data, filename: String) async throws -> String {
        "transcribed note"
    }
}

/// A transport that returns a canned reply so the client's envelope-validation
/// path can be exercised without the broker.
private final class CannedTransport: WatchWireTransporting, @unchecked Sendable {
    let reply: WatchWireReply
    init(_ reply: WatchWireReply) { self.reply = reply }
    func send(_ message: WatchWireMessage) async throws -> WatchWireReply { reply }
}

private final class ThrowingSessionsBackend: WatchPhoneBackend, @unchecked Sendable {
    let error: Error
    init(_ error: Error) { self.error = error }
    func servers() async -> [WatchPhoneServerAccount] {
        [WatchPhoneServerAccount(urlString: "https://alpha.example", displayName: "Alpha")]
    }
    func listSessions(urlString: String, archived: Bool, query: String?, limit: Int) async throws -> [WatchPhoneSessionRow] {
        throw error
    }
    func createSession(urlString: String, profileID: String?, workspace: String?) async throws -> String { "s2" }
    func startChat(urlString: String, sessionID: String, message: String) async throws -> String { "stream-1" }
    func cancelChat(urlString: String, streamID: String) async throws {}
    func transcript(urlString: String, sessionID: String, before: Int?, limit: Int) async throws -> WatchPhoneTranscriptPage {
        WatchPhoneTranscriptPage(blocks: [], nextBefore: nil, isTruncated: false)
    }
    func runPhase(urlString: String, sessionID: String, streamID: String) async throws -> (phase: WatchRunPhase, isTerminal: Bool) {
        (.responding, false)
    }
    func transcribeAudio(urlString: String, data: Data, filename: String) async throws -> String { "transcribed note" }
}

@Suite struct WatchWireValidationTests {
    private let fixedNow: @Sendable () -> Date = { Date(timeIntervalSince1970: 1_700_000_010) }

    @Test func readRejectsAMismatchedEnvelope() async throws {
        // A reply whose scope does not match the request must not populate
        // watch state.
        let foreignScope = ServerScope(
            epoch: InstallationEpoch(rawValue: UUID()),
            server: ServerID(rawValue: UUID()),
            generation: try Generation(1)
        )
        let response = try WatchResponseEnvelope(
            requestID: UUID(),
            scope: foreignScope,
            requestOperationKind: .sessions,
            requestCreatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            requestExpiresAt: Date(timeIntervalSince1970: 1_700_000_060),
            commandContext: nil,
            result: .sessions(try ScopedSnapshot(
                schema: 1,
                scope: foreignScope,
                revision: Revision(1),
                freshness: Freshness(
                    observedAt: Date(timeIntervalSince1970: 1_700_000_010),
                    expiresAt: Date(timeIntervalSince1970: 1_700_000_040),
                    source: .phoneProjection
                ),
                value: BoundedCollection(items: [], isTruncated: false, maximumItems: 100)
            ))
        )
        let client = WatchWireClient(transport: CannedTransport(.envelope(response)), now: fixedNow)
        let scope = ServerScope(
            epoch: InstallationEpoch(rawValue: UUID()),
            server: ServerID(rawValue: UUID()),
            generation: try Generation(1)
        )
        do {
            _ = try await client.refreshSessions(scope: scope, collection: .current, query: nil, localLimit: 10)
            Issue.record("refreshSessions should have thrown for a mismatched envelope")
        } catch is EnvelopeValidationError {
            // expected: scope mismatch rejected the reply
        } catch {
            Issue.record("expected EnvelopeValidationError, got \(error)")
        }
    }

    @Test func authRequiredFailureSurfacesAsADistinctError() async throws {
        // A 401 from the phone's session list must reach the watch as
        // `.authRequired`, not a generic invalidResponse, so the watch can
        // show "sign in on iPhone".
        let backend = ThrowingSessionsBackend(WatchCompanionError.backend(.authRequired))
        let broker = PhoneCompanionBroker(
            epoch: InstallationEpoch(rawValue: UUID()),
            backend: backend,
            now: fixedNow
        )
        let client = WatchWireClient(
            transport: LoopTransport(dispatcher: WatchWireDispatcher(service: broker)),
            now: fixedNow
        )
        let registry = await client.registry()
        let scope = try #require(registry.entries.first?.scope)
        do {
            _ = try await client.refreshSessions(scope: scope, collection: .current, query: nil, localLimit: 10)
            Issue.record("refreshSessions should have thrown")
        } catch WatchCompanionError.backend(.authRequired) {
            // expected
        } catch {
            Issue.record("expected .authRequired, got \(error)")
        }
    }
}
