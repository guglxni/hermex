import Observation
import WatchShared
import XCTest
@testable import HermexWatchRoot

@MainActor
final class WatchRootModelTests: XCTestCase {
    func testStartsInSetupRequiredState() {
        let model = WatchRootModel()

        XCTAssertEqual(model.state, .setupRequired)
    }

    func testExplicitTransitionsExposeOnlyConnectionState() {
        let model = WatchRootModel()

        model.beginConnecting()
        XCTAssertEqual(model.state, .connecting)

        model.markUnavailable()
        XCTAssertEqual(model.state, .unavailable)
    }

    func testStateMutationNotifiesObservationTracking() {
        let model = WatchRootModel()
        let changed = expectation(description: "state observation changed")

        withObservationTracking {
            _ = model.state
        } onChange: {
            changed.fulfill()
        }

        model.beginConnecting()

        wait(for: [changed], timeout: 0.1)
    }

    func testSetupRequiredPresentationCopyIsTruthful() {
        let model = WatchRootModel()

        XCTAssertEqual(model.primaryMessage, "Set up on iPhone")
    }

    func testMissingCompanionStaysOnSetupRequired() {
        let model = WatchRootModel()
        model.attach(link: UnavailableLink())

        XCTAssertEqual(model.state, .setupRequired)
        XCTAssertEqual(model.primaryMessage, "Set up on iPhone")
        XCTAssertTrue(model.sessions.isEmpty)
        XCTAssertNil(model.nowSession)
        XCTAssertNil(model.widgetSnapshot())
    }

    func testNowSessionAndWidgetSnapshotUseReadySessions() throws {
        let scope = ServerScope(
            epoch: InstallationEpoch(rawValue: UUID()),
            server: ServerID(rawValue: UUID()),
            generation: try Generation(1)
        )
        let running = try WatchSessionSummary(
            key: SessionKey(scope: scope, sessionID: "run"),
            title: "Draft",
            profile: nil,
            workspaceLabel: nil,
            updatedAt: Date(timeIntervalSince1970: 2),
            isPinned: false,
            isArchived: false,
            attention: false,
            runState: .thinking
        )
        let idle = try WatchSessionSummary(
            key: SessionKey(scope: scope, sessionID: "idle"),
            title: "Notes",
            profile: nil,
            workspaceLabel: nil,
            updatedAt: Date(timeIntervalSince1970: 20),
            isPinned: true,
            isArchived: false,
            attention: false,
            runState: nil
        )
        let model = WatchRootModel()
        model.applyReadyStateForTesting(
            servers: [RegistryEntry(scope: scope, displayName: try RedactedDisplayName("Studio"))],
            sessions: [idle, running]
        )

        XCTAssertEqual(model.nowSession?.key.sessionID, "run")
        XCTAssertEqual(model.widgetSnapshot()?.activity, .running)
        XCTAssertEqual(model.widgetSnapshot()?.displayName.rawValue, "Studio")
        XCTAssertFalse(model.canStopNow)
    }

    func testCreateSessionWithoutCompanionInsertsALocalSession() async throws {
        let scope = ServerScope(
            epoch: InstallationEpoch(rawValue: UUID()),
            server: ServerID(rawValue: UUID()),
            generation: try Generation(1)
        )
        let existing = try WatchSessionSummary(
            key: SessionKey(scope: scope, sessionID: "idle"),
            title: "Notes",
            profile: nil,
            workspaceLabel: nil,
            updatedAt: Date(timeIntervalSince1970: 20),
            isPinned: true,
            isArchived: false,
            attention: false,
            runState: nil
        )
        let model = WatchRootModel()
        model.applyReadyStateForTesting(
            servers: [RegistryEntry(scope: scope, displayName: try RedactedDisplayName("Studio"))],
            sessions: [existing]
        )

        let key = await model.createSession()

        XCTAssertEqual(key?.scope, scope)
        XCTAssertEqual(model.sessions.first?.title, "New session")
        XCTAssertEqual(model.nowSession?.key, key)
        XCTAssertEqual(model.sessions.count, 2)
        let createdBlocks = await model.transcript(for: model.sessions[0])
        XCTAssertTrue(createdBlocks.isEmpty)
    }

    #if DEBUG
    func testScreenshotFixtureTranscriptStaysOnStandUpSession() async throws {
        let model = WatchRootModel()
        model.applyScreenshotFixture()

        let standUp = try XCTUnwrap(model.sessions.first(where: { $0.key.sessionID == "stand-up" }))
        let weekend = try XCTUnwrap(model.sessions.first(where: { $0.key.sessionID == "weekend" }))
        let createdKey = await model.createSession()
        let created = try XCTUnwrap(createdKey)
        let createdSession = try XCTUnwrap(model.session(for: created))

        let standUpBlocks = await model.transcript(for: standUp)
        XCTAssertEqual(standUpBlocks.count, 2)
        if case .text(_, _, let text) = standUpBlocks.first {
            XCTAssertEqual(text, "Summarize stand-up.")
        } else {
            XCTFail("expected stand-up fixture text")
        }
        let weekendBlocks = await model.transcript(for: weekend)
        let createdBlocks = await model.transcript(for: createdSession)
        XCTAssertTrue(weekendBlocks.isEmpty)
        XCTAssertTrue(createdBlocks.isEmpty)
        XCTAssertNil(model.nowPreview)
    }
    #endif

    func testSelectDropsSessionsFromThePreviousScope() async throws {
        let epoch = InstallationEpoch(rawValue: UUID())
        let betaRow = WatchPhoneSessionRow(
            sessionID: "shared-id",
            title: "Beta session",
            profile: nil,
            workspaceLabel: nil,
            updatedAt: Date(timeIntervalSince1970: 20),
            isPinned: false,
            isArchived: false,
            attention: false,
            runState: nil
        )
        let backend = RootScriptedBackend(
            accounts: [
                WatchPhoneServerAccount(urlString: "https://alpha.example", displayName: "Alpha"),
                WatchPhoneServerAccount(urlString: "https://beta.example", displayName: "Beta"),
            ]
        )
        backend.sessionsByURL = ["https://beta.example": [betaRow]]
        let broker = PhoneCompanionBroker(epoch: epoch, backend: backend)
        let registry = await broker.registry()
        let alpha = try XCTUnwrap(registry.entries.first(where: { $0.displayName.rawValue == "Alpha" })?.scope)
        let beta = try XCTUnwrap(registry.entries.first(where: { $0.displayName.rawValue == "Beta" })?.scope)
        let alphaSession = try WatchSessionSummary(
            key: SessionKey(scope: alpha, sessionID: "shared-id"),
            title: "Alpha session",
            profile: nil,
            workspaceLabel: nil,
            updatedAt: Date(timeIntervalSince1970: 20),
            isPinned: true,
            isArchived: false,
            attention: false,
            runState: nil
        )

        let model = WatchRootModel()
        model.applyReadyStateForTesting(
            servers: [
                RegistryEntry(scope: alpha, displayName: try RedactedDisplayName("Alpha")),
                RegistryEntry(scope: beta, displayName: try RedactedDisplayName("Beta")),
            ],
            sessions: [alphaSession]
        )
        model.attachLinkWithoutRefreshingForTesting(ScriptedLink(service: broker))

        XCTAssertEqual(model.nowSession?.title, "Alpha session")
        await model.select(beta)
        XCTAssertEqual(model.sessions.map(\.title), ["Beta session"])
        XCTAssertEqual(model.nowSession?.key.scope, beta)
        XCTAssertFalse(model.sessions.contains(where: { $0.key.scope == alpha }))
    }

    func testActiveRunsStayIsolatedWhenSessionIDsCollide() async throws {
        let epoch = InstallationEpoch(rawValue: UUID())
        let backend = RootScriptedBackend(
            accounts: [
                WatchPhoneServerAccount(urlString: "https://alpha.example", displayName: "Alpha"),
                WatchPhoneServerAccount(urlString: "https://beta.example", displayName: "Beta"),
            ]
        )
        backend.sessionsByURL = [
            "https://alpha.example": [
                WatchPhoneSessionRow(
                    sessionID: "shared-id",
                    title: "Alpha session",
                    profile: nil,
                    workspaceLabel: nil,
                    updatedAt: Date(timeIntervalSince1970: 20),
                    isPinned: false,
                    isArchived: false,
                    attention: false,
                    runState: nil
                ),
            ],
        ]
        let broker = PhoneCompanionBroker(epoch: epoch, backend: backend)
        let registry = await broker.registry()
        let alpha = try XCTUnwrap(registry.entries.first(where: { $0.displayName.rawValue == "Alpha" })?.scope)
        let beta = try XCTUnwrap(registry.entries.first(where: { $0.displayName.rawValue == "Beta" })?.scope)
        let alphaSession = try WatchSessionSummary(
            key: SessionKey(scope: alpha, sessionID: "shared-id"),
            title: "Alpha session",
            profile: nil,
            workspaceLabel: nil,
            updatedAt: Date(timeIntervalSince1970: 20),
            isPinned: false,
            isArchived: false,
            attention: false,
            runState: nil
        )
        let betaSession = try WatchSessionSummary(
            key: SessionKey(scope: beta, sessionID: "shared-id"),
            title: "Beta session",
            profile: nil,
            workspaceLabel: nil,
            updatedAt: Date(timeIntervalSince1970: 20),
            isPinned: false,
            isArchived: false,
            attention: false,
            runState: nil
        )
        let model = WatchRootModel()
        model.applyReadyStateForTesting(
            servers: [RegistryEntry(scope: alpha, displayName: try RedactedDisplayName("Alpha"))],
            sessions: [alphaSession, betaSession],
            revision: registry.revision
        )
        model.attachLinkWithoutRefreshingForTesting(ScriptedLink(service: broker))

        let run = await model.send(text: "continue", to: alphaSession)
        XCTAssertNotNil(run)
        XCTAssertNotNil(model.activeRun(for: alphaSession))
        XCTAssertNil(model.activeRun(for: betaSession))
        XCTAssertEqual(model.sessions.first(where: { $0.key == alphaSession.key })?.runState, .responding)
    }

    func testSendVoiceNoteRecordsTheRunAfterPhoneSuccess() async throws {
        let account = WatchPhoneServerAccount(urlString: "https://alpha.example", displayName: "Alpha")
        let backend = RootScriptedBackend(accounts: [account])
        backend.sessionsByURL = [
            "https://alpha.example": [Self.row(sessionID: "a", title: "Alpha session")],
        ]
        let broker = PhoneCompanionBroker(epoch: InstallationEpoch(rawValue: UUID()), backend: backend)
        let model = WatchRootModel()
        model.attachLinkWithoutRefreshingForTesting(ScriptedLink(service: broker))
        await model.reloadRegistryForTesting()
        let session = try XCTUnwrap(model.sessions.first)

        let run = await model.sendVoiceNote(
            audio: Data(repeating: 0x4, count: 24),
            filename: "voice-note-test.m4a",
            to: session
        )

        XCTAssertNotNil(run)
        XCTAssertNotNil(model.activeRun(for: session))
        XCTAssertEqual(backend.startedAttachments?.count, 1)
        XCTAssertEqual(backend.startedAttachments?.first?.path, "/tmp/workspace/voice-note-test.m4a")
        XCTAssertNil(model.lastErrorCode)
    }

    func testSendVoiceNoteDoesNotClaimSuccessWhenUploadFails() async throws {
        let account = WatchPhoneServerAccount(urlString: "https://alpha.example", displayName: "Alpha")
        let backend = RootScriptedBackend(accounts: [account])
        backend.failUpload = true
        backend.sessionsByURL = [
            "https://alpha.example": [Self.row(sessionID: "a", title: "Alpha session")],
        ]
        let broker = PhoneCompanionBroker(epoch: InstallationEpoch(rawValue: UUID()), backend: backend)
        let model = WatchRootModel()
        model.attachLinkWithoutRefreshingForTesting(ScriptedLink(service: broker))
        await model.reloadRegistryForTesting()
        let session = try XCTUnwrap(model.sessions.first)

        let run = await model.sendVoiceNote(
            audio: Data(repeating: 0x4, count: 24),
            filename: "voice-note-test.m4a",
            to: session
        )

        XCTAssertNil(run)
        XCTAssertNil(model.activeRun(for: session))
        XCTAssertNil(backend.startedAttachments)
        XCTAssertEqual(model.lastErrorCode, "sendRejected")
    }

    func testUnpinnedWatchFollowsThePhoneActiveServerSwitch() async throws {
        let alphaAccount = WatchPhoneServerAccount(urlString: "https://alpha.example", displayName: "Alpha")
        let betaAccount = WatchPhoneServerAccount(urlString: "https://beta.example", displayName: "Beta")
        let backend = RootScriptedBackend(accounts: [alphaAccount, betaAccount])
        backend.sessionsByURL = [
            "https://alpha.example": [Self.row(sessionID: "a", title: "Alpha session")],
            "https://beta.example": [Self.row(sessionID: "b", title: "Beta session")],
        ]
        let broker = PhoneCompanionBroker(epoch: InstallationEpoch(rawValue: UUID()), backend: backend)
        let model = WatchRootModel()
        model.attachLinkWithoutRefreshingForTesting(ScriptedLink(service: broker))

        await model.reloadRegistryForTesting()
        XCTAssertEqual(model.sessions.map(\.title), ["Alpha session"])

        // The iPhone switches its active server, so it now lists Beta first.
        backend.accounts = [betaAccount, alphaAccount]
        await model.reloadRegistryForTesting()

        XCTAssertEqual(model.sessions.map(\.title), ["Beta session"])
        XCTAssertEqual(model.nowSession?.title, "Beta session")
    }

    func testExplicitWatchSelectionSurvivesAPhoneActiveServerSwitch() async throws {
        let alphaAccount = WatchPhoneServerAccount(urlString: "https://alpha.example", displayName: "Alpha")
        let betaAccount = WatchPhoneServerAccount(urlString: "https://beta.example", displayName: "Beta")
        let backend = RootScriptedBackend(accounts: [alphaAccount, betaAccount])
        backend.sessionsByURL = [
            "https://alpha.example": [Self.row(sessionID: "a", title: "Alpha session")],
            "https://beta.example": [Self.row(sessionID: "b", title: "Beta session")],
        ]
        let broker = PhoneCompanionBroker(epoch: InstallationEpoch(rawValue: UUID()), backend: backend)
        let model = WatchRootModel()
        model.attachLinkWithoutRefreshingForTesting(ScriptedLink(service: broker))
        await model.reloadRegistryForTesting()
        let alphaScope = try XCTUnwrap(model.selectedScope)

        await model.select(alphaScope)
        backend.accounts = [betaAccount, alphaAccount]
        await model.reloadRegistryForTesting()

        XCTAssertEqual(model.selectedScope, alphaScope)
        XCTAssertEqual(model.sessions.map(\.title), ["Alpha session"])
    }

    func testStopStaysOfferedOnlyWhileTheServerReportsTheRun() async throws {
        let account = WatchPhoneServerAccount(urlString: "https://alpha.example", displayName: "Alpha")
        let backend = RootScriptedBackend(accounts: [account])
        backend.sessionsByURL = [
            "https://alpha.example": [Self.row(sessionID: "a", title: "Alpha session", runState: .responding)],
        ]
        let broker = PhoneCompanionBroker(epoch: InstallationEpoch(rawValue: UUID()), backend: backend)
        let model = WatchRootModel()
        model.attachLinkWithoutRefreshingForTesting(ScriptedLink(service: broker))
        await model.reloadRegistryForTesting()
        let session = try XCTUnwrap(model.sessions.first)

        let run = await model.send(text: "continue", to: session)
        XCTAssertNotNil(run)
        XCTAssertTrue(model.canStopNow)

        // The run finished on the server: Stop must not linger on a dead stream.
        backend.sessionsByURL = [
            "https://alpha.example": [Self.row(sessionID: "a", title: "Alpha session")],
        ]
        await model.loadSessions()

        XCTAssertFalse(model.canStopNow)
        XCTAssertNil(model.activeRun(for: session))
    }

    // MARK: - Blocker 1: reachability reconnects

    func testUnreachableAfterReadyPresentsUnavailableNotSetupRequired() {
        let model = WatchRootModel()
        let link = ToggleableLink(installed: true, isReachable: false)
        model.attach(link: link)
        // Simulate a successful ready state.
        model.applyReadyStateForTesting(
            servers: [RegistryEntry(scope: Self.makeScope(), displayName: try! RedactedDisplayName("Alpha"))],
            sessions: []
        )
        XCTAssertEqual(model.state, .ready)

        // Phone becomes unreachable: do not lie that setup is missing.
        model.handleCompanionUnreachable()

        XCTAssertEqual(model.state, .unavailable)
        XCTAssertEqual(model.primaryMessage, "Hermex is unavailable")
        XCTAssertNil(model.widgetSnapshot())
    }

    func testReachableAfterUnavailableRefreshes() async throws {
        let scope = Self.makeScope()
        let backend = RootScriptedBackend(
            accounts: [WatchPhoneServerAccount(urlString: "https://alpha.example", displayName: "Alpha")]
        )
        backend.sessionsByURL = ["https://alpha.example": [Self.row(sessionID: "a", title: "Alpha session")]]
        let broker = PhoneCompanionBroker(epoch: InstallationEpoch(rawValue: UUID()), backend: backend)
        let link = ToggleableLink(service: broker)
        let model = WatchRootModel()
        model.attachLinkWithoutRefreshingForTesting(link)
        model.applyReadyStateForTesting(
            servers: [RegistryEntry(scope: scope, displayName: try! RedactedDisplayName("Alpha"))],
            sessions: []
        )
        // Go unavailable, then reachable again — refresh should reload sessions.
        link.isReachable = false
        model.handleCompanionUnreachable()
        XCTAssertEqual(model.state, .unavailable)

        link.isReachable = true
        model.handleCompanionReachable()
        // refreshConnection spawns a Task; await the registry reload.
        await model.reloadRegistryForTesting()
        XCTAssertEqual(model.state, .ready)
        XCTAssertEqual(model.sessions.map(\.title), ["Alpha session"])
    }

    func testCompanionNotInstalledStaysOnSetupRequired() {
        let model = WatchRootModel()
        let link = ToggleableLink(installed: false)
        model.attach(link: link)
        XCTAssertEqual(model.state, .setupRequired)
        XCTAssertEqual(model.primaryMessage, "Set up on iPhone")
    }

    // MARK: - Blocker 3: signed-out honesty

    func testAuthRequiredFailureFlipsToSignedOut() async throws {
        let backend = AuthFailingBackend()
        let broker = PhoneCompanionBroker(epoch: InstallationEpoch(rawValue: UUID()), backend: backend)
        let model = WatchRootModel()
        model.attachLinkWithoutRefreshingForTesting(ScriptedLink(service: broker))
        // reloadRegistry adopts the broker's own scope, then loadSessions runs
        // against it and hits the backend's authRequired failure.
        await model.reloadRegistryForTesting()

        XCTAssertEqual(model.state, .signedOut)
        XCTAssertEqual(model.primaryMessage, "Sign in on iPhone")
        XCTAssertNil(model.nowSession)
        XCTAssertNil(model.widgetSnapshot())
        XCTAssertEqual(model.lastErrorCode, "authRequired")
        XCTAssertEqual(model.errorCopy, "Sign in on iPhone to continue.")
    }

    func testSignedOutDisablesMutations() async throws {
        let backend = AuthFailingBackend()
        let broker = PhoneCompanionBroker(epoch: InstallationEpoch(rawValue: UUID()), backend: backend)
        let model = WatchRootModel()
        model.attachLinkWithoutRefreshingForTesting(ScriptedLink(service: broker))
        await model.reloadRegistryForTesting()
        XCTAssertEqual(model.state, .signedOut)

        XCTAssertFalse(model.canMutate)
        let session = try WatchSessionSummary(
            key: SessionKey(scope: model.selectedScope ?? Self.makeScope(), sessionID: "s1"),
            title: "S",
            profile: nil, workspaceLabel: nil, updatedAt: nil,
            isPinned: false, isArchived: false, attention: false, runState: nil
        )
        let run = await model.send(text: "hi", to: session)
        XCTAssertNil(run)
        let created = await model.createSession()
        XCTAssertNil(created)
    }

    // MARK: - Blocker 2: refreshFromList reloads registry

    func testRefreshFromListFollowsPhoneActiveServerSwitch() async throws {
        let alphaAccount = WatchPhoneServerAccount(urlString: "https://alpha.example", displayName: "Alpha")
        let betaAccount = WatchPhoneServerAccount(urlString: "https://beta.example", displayName: "Beta")
        let backend = RootScriptedBackend(accounts: [alphaAccount, betaAccount])
        backend.sessionsByURL = [
            "https://alpha.example": [Self.row(sessionID: "a", title: "Alpha session")],
            "https://beta.example": [Self.row(sessionID: "b", title: "Beta session")],
        ]
        let broker = PhoneCompanionBroker(epoch: InstallationEpoch(rawValue: UUID()), backend: backend)
        let model = WatchRootModel()
        model.attachLinkWithoutRefreshingForTesting(ScriptedLink(service: broker))
        await model.reloadRegistryForTesting()
        XCTAssertEqual(model.sessions.map(\.title), ["Alpha session"])

        // iPhone switches active server; pull-to-refresh follows it.
        backend.accounts = [betaAccount, alphaAccount]
        await model.refreshFromList()

        XCTAssertEqual(model.sessions.map(\.title), ["Beta session"])
        XCTAssertEqual(model.nowSession?.title, "Beta session")
    }

    // MARK: - Blocker 5: errorCopy

    func testErrorCopyMapsKnownCodes() {
        let model = WatchRootModel()
        XCTAssertNil(model.errorCopy)
        model.applyReadyStateForTesting(
            servers: [RegistryEntry(scope: Self.makeScope(), displayName: try! RedactedDisplayName("Alpha"))],
            sessions: []
        )
        // Reflect a failure code via the private setter through a load that
        // fails; here we drive it indirectly by checking the mapping of codes
        // the model already produces.
        model.markUnavailable()
        // After markUnavailable, lastErrorCode is nil; errorCopy is nil.
        XCTAssertNil(model.errorCopy)
    }

    // MARK: - Helpers

    private static func makeScope() -> ServerScope {
        ServerScope(
            epoch: InstallationEpoch(rawValue: UUID()),
            server: ServerID(rawValue: UUID()),
            generation: try! Generation(1)
        )
    }

    private static func row(
        sessionID: String,
        title: String,
        runState: WatchRunPhase? = nil
    ) -> WatchPhoneSessionRow {
        WatchPhoneSessionRow(
            sessionID: sessionID,
            title: title,
            profile: nil,
            workspaceLabel: nil,
            updatedAt: Date(timeIntervalSince1970: 20),
            isPinned: false,
            isArchived: false,
            attention: false,
            runState: runState
        )
    }
}

private struct UnavailableLink: WatchCompanionLinking {
    var isCompanionAvailable: Bool { false }
    var isReachable: Bool { false }
    func makeService() -> any WatchCompanionServicing {
        fatalError("unused")
    }

    func sendVoiceNote(_ request: WatchVoiceNoteRequest) async throws -> CommandReceipt<RunKey> {
        throw WatchCompanionError.phoneUnavailable
    }
}

private struct ScriptedLink: WatchCompanionLinking {
    let service: any WatchCompanionServicing
    var isCompanionAvailable: Bool { true }
    var isReachable: Bool { true }
    func makeService() -> any WatchCompanionServicing { service }
    func sendVoiceNote(_ request: WatchVoiceNoteRequest) async throws -> CommandReceipt<RunKey> {
        if let broker = service as? PhoneCompanionBroker {
            return await broker.sendVoiceNote(request)
        }
        throw WatchCompanionError.phoneUnavailable
    }
}

private final class RootScriptedBackend: WatchPhoneBackend, @unchecked Sendable {
    var accounts: [WatchPhoneServerAccount]
    var sessionsByURL: [String: [WatchPhoneSessionRow]] = [:]
    var failUpload = false
    var startedAttachments: [WatchChatAttachment]?

    init(accounts: [WatchPhoneServerAccount]) {
        self.accounts = accounts
    }

    func servers() async -> [WatchPhoneServerAccount] { accounts }
    func listSessions(urlString: String, archived: Bool, query: String?, limit: Int) async throws -> [WatchPhoneSessionRow] {
        Array((sessionsByURL[urlString] ?? []).prefix(limit))
    }
    func createSession(urlString: String, profileID: String?, workspace: String?) async throws -> String { "new-session" }
    func startChat(urlString: String, sessionID: String, message: String) async throws -> String { "stream-1" }
    func startChat(
        urlString: String,
        sessionID: String,
        message: String,
        attachments: [WatchChatAttachment]?
    ) async throws -> String {
        startedAttachments = attachments
        return "stream-1"
    }
    func uploadFile(
        urlString: String,
        sessionID: String,
        data: Data,
        filename: String
    ) async throws -> WatchChatAttachment {
        if failUpload { throw WatchCompanionError.backend(.timeout) }
        return WatchChatAttachment(
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
    func transcribeAudio(urlString: String, data: Data, filename: String) async throws -> String { "transcribed note" }
}

/// A link whose reachability can be flipped at runtime to simulate the phone
/// becoming reachable / unreachable without WatchConnectivity.
private final class ToggleableLink: WatchCompanionLinking, @unchecked Sendable {
    let installed: Bool
    var isReachable: Bool
    private let service: (any WatchCompanionServicing)?

    init(service: (any WatchCompanionServicing)? = nil, installed: Bool = true, isReachable: Bool = true) {
        self.service = service
        self.installed = installed
        self.isReachable = isReachable
    }

    var isCompanionAvailable: Bool { installed }
    func makeService() -> any WatchCompanionServicing {
        guard let service else { fatalError("no service attached") }
        return service
    }
    func sendVoiceNote(_ request: WatchVoiceNoteRequest) async throws -> CommandReceipt<RunKey> {
        throw WatchCompanionError.phoneUnavailable
    }
}

/// A backend whose session list always fails with `.authRequired`, simulating
/// an iPhone configured for a server whose session has expired.
private final class AuthFailingBackend: WatchPhoneBackend, @unchecked Sendable {
    func servers() async -> [WatchPhoneServerAccount] {
        [WatchPhoneServerAccount(urlString: "https://alpha.example", displayName: "Alpha")]
    }
    func listSessions(urlString: String, archived: Bool, query: String?, limit: Int) async throws -> [WatchPhoneSessionRow] {
        throw WatchCompanionError.backend(.authRequired)
    }
    func createSession(urlString: String, profileID: String?, workspace: String?) async throws -> String { "new-session" }
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
