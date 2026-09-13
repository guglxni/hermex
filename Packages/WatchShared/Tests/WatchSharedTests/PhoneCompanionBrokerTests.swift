import Foundation
import Testing
@testable import WatchShared

@Suite struct PhoneCompanionBrokerTests {
    private final class ScriptedBackend: WatchPhoneBackend, @unchecked Sendable {
        var accounts: [WatchPhoneServerAccount]
        var sessions: [WatchPhoneSessionRow]
        var createdSessionID = "new-session"
        var startedStreamID = "stream-1"
        var cancelledStreamIDs: [String] = []
        var transcriptPage = WatchPhoneTranscriptPage(
            blocks: [WatchPhoneTranscriptPage.Block(id: "m1", role: .user, text: "hello")],
            nextBefore: nil,
            isTruncated: false
        )
        var phase: (WatchRunPhase, Bool) = (.responding, false)
        var failSessions = false
        var failTranscribe = false
        var failUpload = false
        var failStartChat = false
        var sessionsByURL: [String: [WatchPhoneSessionRow]] = [:]
        var listedURLs: [String] = []
        var transcribedFilenames: [String] = []
        var uploaded: [(sessionID: String, filename: String, bytes: Int)] = []
        var startedChats: [(sessionID: String, message: String, attachments: [WatchChatAttachment]?)] = []

        init(
            accounts: [WatchPhoneServerAccount],
            sessions: [WatchPhoneSessionRow]
        ) {
            self.accounts = accounts
            self.sessions = sessions
        }

        func servers() async -> [WatchPhoneServerAccount] { accounts }
        func listSessions(urlString: String, archived: Bool, query: String?, limit: Int) async throws -> [WatchPhoneSessionRow] {
            listedURLs.append(urlString)
            if failSessions { throw WatchCompanionError.backend(.timeout) }
            let source = sessionsByURL[urlString] ?? (sessionsByURL.isEmpty ? sessions : [])
            let filtered = source.filter { archived ? $0.isArchived : !$0.isArchived }
            if let query, !query.isEmpty {
                return Array(filtered.filter { $0.title.localizedCaseInsensitiveContains(query) }.prefix(limit))
            }
            return Array(filtered.prefix(limit))
        }
        func createSession(urlString: String, profileID: String?, workspace: String?) async throws -> String { createdSessionID }
        func startChat(urlString: String, sessionID: String, message: String) async throws -> String {
            try await startChat(urlString: urlString, sessionID: sessionID, message: message, attachments: nil)
        }
        func startChat(
            urlString: String,
            sessionID: String,
            message: String,
            attachments: [WatchChatAttachment]?
        ) async throws -> String {
            startedChats.append((sessionID, message, attachments))
            if failStartChat { throw WatchCompanionError.backend(.timeout) }
            return startedStreamID
        }
        func uploadFile(
            urlString: String,
            sessionID: String,
            data: Data,
            filename: String
        ) async throws -> WatchChatAttachment {
            uploaded.append((sessionID, filename, data.count))
            if failUpload { throw WatchCompanionError.backend(.timeout) }
            return WatchChatAttachment(
                name: filename,
                path: "/tmp/workspace/\(filename)",
                mime: "audio/m4a",
                size: data.count,
                isImage: false
            )
        }
        func cancelChat(urlString: String, streamID: String) async throws { cancelledStreamIDs.append(streamID) }
        func transcript(urlString: String, sessionID: String, before: Int?, limit: Int) async throws -> WatchPhoneTranscriptPage { transcriptPage }
        func runPhase(urlString: String, sessionID: String, streamID: String) async throws -> (phase: WatchRunPhase, isTerminal: Bool) { phase }
        func transcribeAudio(urlString: String, data: Data, filename: String) async throws -> String {
            transcribedFilenames.append(filename)
            if failTranscribe { throw WatchCompanionError.backend(.timeout) }
            return "transcribed note"
        }
    }

    private func makeBroker(_ backend: ScriptedBackend, epoch: InstallationEpoch = InstallationEpoch(rawValue: UUID())) -> PhoneCompanionBroker {
        PhoneCompanionBroker(epoch: epoch, backend: backend, now: { Date(timeIntervalSince1970: 1_700_000_000) })
    }

    @Test func registryMapsServersIntoScopedEntries() async throws {
        let backend = ScriptedBackend(
            accounts: [
                WatchPhoneServerAccount(urlString: "https://alpha.example", displayName: "Alpha"),
                WatchPhoneServerAccount(urlString: "https://beta.example", displayName: "Beta"),
            ],
            sessions: []
        )
        let epoch = InstallationEpoch(rawValue: UUID())
        let broker = makeBroker(backend, epoch: epoch)

        let snapshot = await broker.registry()
        #expect(snapshot.epoch == epoch)
        #expect(snapshot.entries.count == 2)
        #expect(snapshot.entries.map(\.displayName.rawValue) == ["Alpha", "Beta"])
        #expect(snapshot.entries[0].scope.server == ServerID.derived(from: "https://alpha.example"))
        #expect(Set(snapshot.entries.map(\.scope.server)).count == 2)
    }

    @Test func sendStartsARunOnTheScopedServer() async throws {
        let row = WatchPhoneSessionRow(
            sessionID: "s1",
            title: "Planning",
            profile: "default",
            workspaceLabel: nil,
            updatedAt: Date(timeIntervalSince1970: 10),
            isPinned: true,
            isArchived: false,
            attention: false,
            runState: nil
        )
        let backend = ScriptedBackend(
            accounts: [WatchPhoneServerAccount(urlString: "https://alpha.example", displayName: "Alpha")],
            sessions: [row]
        )
        let broker = makeBroker(backend)
        let registry = await broker.registry()
        let scope = try #require(registry.entries.first?.scope)
        let session = try SessionKey(scope: scope, sessionID: "s1")
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let context = try CommandContext(
            stableCommandID: CommandID(rawValue: UUID()),
            scope: scope,
            expectedRevision: registry.revision,
            createdAt: created,
            expiresAt: created.addingTimeInterval(60)
        )

        let receipt = await broker.send(text: "continue", to: session, context: context)
        #expect(receipt.receipt.phase == .acknowledged)
        #expect(receipt.receipt.operationKind == .send)
        #expect(receipt.value?.streamID == "stream-1")
        #expect(receipt.value?.session == session)
    }

    @Test func sendRejectsUnknownScope() async throws {
        let backend = ScriptedBackend(
            accounts: [WatchPhoneServerAccount(urlString: "https://alpha.example", displayName: "Alpha")],
            sessions: []
        )
        let broker = makeBroker(backend)
        _ = await broker.registry()
        let foreign = ServerScope(
            epoch: InstallationEpoch(rawValue: UUID()),
            server: ServerID(rawValue: UUID()),
            generation: try Generation(1)
        )
        let session = try SessionKey(scope: foreign, sessionID: "s1")
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let context = try CommandContext(
            stableCommandID: CommandID(rawValue: UUID()),
            scope: foreign,
            expectedRevision: Revision(1),
            createdAt: created,
            expiresAt: created.addingTimeInterval(60)
        )

        let receipt = await broker.send(text: "nope", to: session, context: context)
        #expect(receipt.receipt.phase == .rejected)
        #expect(receipt.value == nil)
    }

    @Test func refreshSessionsAndTranscriptStayOnTheActiveScope() async throws {
        let backend = ScriptedBackend(
            accounts: [WatchPhoneServerAccount(urlString: "https://alpha.example", displayName: "Alpha")],
            sessions: [
                WatchPhoneSessionRow(
                    sessionID: "s1",
                    title: "Planning",
                    profile: nil,
                    workspaceLabel: "~/src",
                    updatedAt: nil,
                    isPinned: false,
                    isArchived: false,
                    attention: true,
                    runState: .responding
                ),
            ]
        )
        let broker = makeBroker(backend)
        let registry = await broker.registry()
        let scope = try #require(registry.entries.first?.scope)

        let sessions = try await broker.refreshSessions(scope: scope, collection: .current, query: nil, localLimit: 20)
        #expect(sessions.value.items.count == 1)
        #expect(sessions.value.items[0].title == "Planning")
        #expect(sessions.value.items[0].key.scope == scope)

        let transcript = try await broker.transcript(key: sessions.value.items[0].key, before: nil, limit: 20)
        #expect(transcript.value.blocks.count == 1)
        if case .text(_, .user, let text) = transcript.value.blocks[0] {
            #expect(text == "hello")
        } else {
            Issue.record("expected a user text block")
        }
    }

    @Test func registryRefreshKeepsRevisionWhenMembershipIsUnchanged() async {
        let backend = ScriptedBackend(
            accounts: [WatchPhoneServerAccount(urlString: "https://alpha.example", displayName: "Alpha")],
            sessions: []
        )
        let broker = makeBroker(backend)
        let first = await broker.registry()
        let second = await broker.registry()
        #expect(first.revision == second.revision)
        #expect(first.entries == second.entries)
        #expect(first.generatedAt == second.generatedAt)
    }

    @Test func activeServerOrderChangeIsANewRevision() async throws {
        let alpha = WatchPhoneServerAccount(urlString: "https://alpha.example", displayName: "Alpha")
        let beta = WatchPhoneServerAccount(urlString: "https://beta.example", displayName: "Beta")
        let backend = ScriptedBackend(accounts: [alpha, beta], sessions: [])
        let broker = makeBroker(backend)
        let first = await broker.registry()
        #expect(first.entries.map(\.displayName.rawValue) == ["Alpha", "Beta"])

        // The phone switched its active server, so it lists Beta first.
        backend.accounts = [beta, alpha]
        let second = await broker.registry()

        #expect(second.entries.map(\.displayName.rawValue) == ["Beta", "Alpha"])
        #expect(second.revision.rawValue > first.revision.rawValue)
        #expect(second.entries.map(\.scope.generation.rawValue) == [1, 1])
    }

    @Test func duplicateServerURLCollapsesInsteadOfEmptyingTheRegistry() async throws {
        let backend = ScriptedBackend(
            accounts: [
                WatchPhoneServerAccount(urlString: "https://alpha.example", displayName: "Alpha"),
                WatchPhoneServerAccount(urlString: "https://alpha.example", displayName: "Alpha copy"),
            ],
            sessions: []
        )
        let broker = makeBroker(backend)

        let snapshot = await broker.registry()

        #expect(snapshot.entries.map(\.displayName.rawValue) == ["Alpha"])
        #expect(snapshot.revision.rawValue == 1)
    }

    @Test func removedServerReappearsAtANewerGeneration() async throws {
        let backend = ScriptedBackend(
            accounts: [WatchPhoneServerAccount(urlString: "https://alpha.example", displayName: "Alpha")],
            sessions: []
        )
        let broker = makeBroker(backend)
        let first = await broker.registry()
        let original = try #require(first.entries.first?.scope)
        #expect(original.generation.rawValue == 1)

        backend.accounts = []
        let empty = await broker.registry()
        #expect(empty.entries.isEmpty)
        #expect(empty.revision.rawValue > first.revision.rawValue)

        backend.accounts = [WatchPhoneServerAccount(urlString: "https://alpha.example", displayName: "Alpha")]
        let restored = await broker.registry()
        let readded = try #require(restored.entries.first?.scope)
        #expect(readded.server == original.server)
        #expect(readded.generation.rawValue == 2)
        #expect(restored.revision.rawValue > empty.revision.rawValue)
    }

    @Test func sessionsStayIsolatedToTheScopedServerURL() async throws {
        let alphaRow = WatchPhoneSessionRow(
            sessionID: "shared-id",
            title: "Alpha session",
            profile: nil,
            workspaceLabel: nil,
            updatedAt: nil,
            isPinned: false,
            isArchived: false,
            attention: false,
            runState: nil
        )
        let betaRow = WatchPhoneSessionRow(
            sessionID: "shared-id",
            title: "Beta session",
            profile: nil,
            workspaceLabel: nil,
            updatedAt: nil,
            isPinned: false,
            isArchived: false,
            attention: false,
            runState: nil
        )
        let backend = ScriptedBackend(
            accounts: [
                WatchPhoneServerAccount(urlString: "https://alpha.example", displayName: "Alpha"),
                WatchPhoneServerAccount(urlString: "https://beta.example", displayName: "Beta"),
            ],
            sessions: []
        )
        backend.sessionsByURL = [
            "https://alpha.example": [alphaRow],
            "https://beta.example": [betaRow],
        ]
        let broker = makeBroker(backend)
        let registry = await broker.registry()
        let alpha = try #require(registry.entries.first(where: { $0.displayName.rawValue == "Alpha" })?.scope)
        let beta = try #require(registry.entries.first(where: { $0.displayName.rawValue == "Beta" })?.scope)

        let alphaSessions = try await broker.refreshSessions(scope: alpha, collection: .current, query: nil, localLimit: 20)
        let betaSessions = try await broker.refreshSessions(scope: beta, collection: .current, query: nil, localLimit: 20)
        #expect(alphaSessions.value.items.map(\.title) == ["Alpha session"])
        #expect(betaSessions.value.items.map(\.title) == ["Beta session"])
        #expect(alphaSessions.value.items[0].key.scope == alpha)
        #expect(betaSessions.value.items[0].key.scope == beta)
        #expect(backend.listedURLs == ["https://alpha.example", "https://beta.example"])
    }

    @Test func stopRejectsRunsTheWatchDidNotStart() async throws {
        let backend = ScriptedBackend(
            accounts: [WatchPhoneServerAccount(urlString: "https://alpha.example", displayName: "Alpha")],
            sessions: []
        )
        let broker = makeBroker(backend)
        let registry = await broker.registry()
        let scope = try #require(registry.entries.first?.scope)
        let run = try RunKey(session: SessionKey(scope: scope, sessionID: "s1"), streamID: "phone-stream")
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let context = try CommandContext(
            stableCommandID: CommandID(rawValue: UUID()),
            scope: scope,
            expectedRevision: registry.revision,
            createdAt: created,
            expiresAt: created.addingTimeInterval(60)
        )

        let receipt = await broker.stop(run: run, context: context)
        #expect(receipt.receipt.phase == .rejected)
        #expect(receipt.value == nil)
        #expect(backend.cancelledStreamIDs.isEmpty)
    }

    @Test func stopCancelsAWatchStartedRun() async throws {
        let backend = ScriptedBackend(
            accounts: [WatchPhoneServerAccount(urlString: "https://alpha.example", displayName: "Alpha")],
            sessions: []
        )
        let broker = makeBroker(backend)
        let registry = await broker.registry()
        let scope = try #require(registry.entries.first?.scope)
        let session = try SessionKey(scope: scope, sessionID: "s1")
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let context = try CommandContext(
            stableCommandID: CommandID(rawValue: UUID()),
            scope: scope,
            expectedRevision: registry.revision,
            createdAt: created,
            expiresAt: created.addingTimeInterval(60)
        )

        let started = await broker.send(text: "continue", to: session, context: context)
        let run = try #require(started.value)
        let receipt = await broker.stop(run: run, context: context)
        #expect(receipt.receipt.phase == .acknowledged)
        #expect(backend.cancelledStreamIDs == ["stream-1"])
    }

    @Test func transcribeVoiceNoteUsesTheScopedServer() async throws {
        let backend = ScriptedBackend(
            accounts: [WatchPhoneServerAccount(urlString: "https://alpha.example", displayName: "Alpha")],
            sessions: []
        )
        let broker = makeBroker(backend)
        let registry = await broker.registry()
        let scope = try #require(registry.entries.first?.scope)
        let request = try WatchVoiceNoteRequest(
            scope: scope,
            expectedRevision: registry.revision,
            session: try SessionKey(scope: scope, sessionID: "s1"),
            filename: "voice-note-test.m4a",
            audio: Data(repeating: 0x2, count: 24)
        )
        #expect(try await broker.transcribeVoiceNote(request) == "transcribed note")
    }

    @Test func sendVoiceNoteUploadsTheClipAndStartsChatWithTheAttachment() async throws {
        let backend = ScriptedBackend(
            accounts: [WatchPhoneServerAccount(urlString: "https://alpha.example", displayName: "Alpha")],
            sessions: []
        )
        let broker = makeBroker(backend)
        let registry = await broker.registry()
        let scope = try #require(registry.entries.first?.scope)
        let session = try SessionKey(scope: scope, sessionID: "s1")
        let audio = Data(repeating: 0x2, count: 24)
        let request = try WatchVoiceNoteRequest(
            scope: scope,
            expectedRevision: registry.revision,
            session: session,
            filename: "voice-note-test.m4a",
            audio: audio
        )

        let receipt = await broker.sendVoiceNote(request)

        #expect(receipt.receipt.phase == .acknowledged)
        #expect(receipt.receipt.operationKind == .send)
        #expect(receipt.value?.streamID == "stream-1")
        #expect(receipt.value?.session == session)
        #expect(backend.transcribedFilenames == ["voice-note-test.m4a"])
        #expect(backend.uploaded.map(\.sessionID) == ["s1"])
        #expect(backend.uploaded.map(\.filename) == ["voice-note-test.m4a"])
        #expect(backend.uploaded.map(\.bytes) == [audio.count])
        #expect(backend.startedChats.count == 1)
        #expect(backend.startedChats[0].sessionID == "s1")
        #expect(backend.startedChats[0].message == "transcribed note")
        #expect(backend.startedChats[0].message.contains("[Attached files:") == false)
        let attachments = try #require(backend.startedChats[0].attachments)
        #expect(attachments.count == 1)
        #expect(attachments[0].path == "/tmp/workspace/voice-note-test.m4a")
        #expect(attachments[0].mime == "audio/m4a")
        #expect(attachments[0].isImage == false)
    }

    @Test func sendVoiceNoteRejectsWhenUploadFailsAfterTranscribe() async throws {
        let backend = ScriptedBackend(
            accounts: [WatchPhoneServerAccount(urlString: "https://alpha.example", displayName: "Alpha")],
            sessions: []
        )
        backend.failUpload = true
        let broker = makeBroker(backend)
        let registry = await broker.registry()
        let scope = try #require(registry.entries.first?.scope)
        let request = try WatchVoiceNoteRequest(
            scope: scope,
            expectedRevision: registry.revision,
            session: try SessionKey(scope: scope, sessionID: "s1"),
            filename: "voice-note-test.m4a",
            audio: Data(repeating: 0x2, count: 24)
        )

        let receipt = await broker.sendVoiceNote(request)

        #expect(receipt.receipt.phase == .rejected)
        #expect(receipt.value == nil)
        #expect(backend.transcribedFilenames == ["voice-note-test.m4a"])
        #expect(backend.startedChats.isEmpty)
    }

    @Test func sendVoiceNoteRejectsWhenTranscribeFails() async throws {
        let backend = ScriptedBackend(
            accounts: [WatchPhoneServerAccount(urlString: "https://alpha.example", displayName: "Alpha")],
            sessions: []
        )
        backend.failTranscribe = true
        let broker = makeBroker(backend)
        let registry = await broker.registry()
        let scope = try #require(registry.entries.first?.scope)
        let request = try WatchVoiceNoteRequest(
            scope: scope,
            expectedRevision: registry.revision,
            session: try SessionKey(scope: scope, sessionID: "s1"),
            filename: "voice-note-test.m4a",
            audio: Data(repeating: 0x2, count: 24)
        )

        let receipt = await broker.sendVoiceNote(request)

        #expect(receipt.receipt.phase == .rejected)
        #expect(receipt.value == nil)
        #expect(backend.uploaded.isEmpty)
        #expect(backend.startedChats.isEmpty)
    }

    @Test func derivedServerIDIsStableAndUrlFree() {
        let first = ServerID.derived(from: "https://alpha.example")
        let second = ServerID.derived(from: "https://alpha.example")
        let other = ServerID.derived(from: "https://beta.example")
        #expect(first == second)
        #expect(first != other)
        #expect(first.rawValue.uuidString.contains("://") == false)
    }
}
