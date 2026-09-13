import Foundation
import Observation
import WatchShared

public protocol WatchCompanionLinking: Sendable {
    var isCompanionAvailable: Bool { get }
    var isReachable: Bool { get }
    func makeService() -> any WatchCompanionServicing
    func sendVoiceNote(_ request: WatchVoiceNoteRequest) async throws -> CommandReceipt<RunKey>
}

@MainActor
@Observable
public final class WatchRootModel {
    public private(set) var state: WatchLaunchState
    public private(set) var servers: [RegistryEntry]
    public private(set) var selectedScope: ServerScope?
    public private(set) var sessions: [WatchSessionSummary]
    public private(set) var registryRevision: Revision
    public private(set) var lastErrorCode: String?
    public private(set) var nowPreview: String?
    public private(set) var focusedSessionKey: SessionKey?

    private var link: (any WatchCompanionLinking)?
    private var activeRunBySession: [SessionKey: RunKey] = [:]
    private var fixtureTranscriptBySessionID: [String: [WatchTranscriptBlock]] = [:]
    /// The watch has no server picker, so it follows whichever server the iPhone
    /// reports first (its active one). An explicit `select(_:)` pins the watch to
    /// that scope and stops the follow.
    private var followsPhoneActiveServer = true

    public init() {
        state = .setupRequired
        servers = []
        selectedScope = nil
        sessions = []
        registryRevision = Revision(0)
        lastErrorCode = nil
        nowPreview = nil
        focusedSessionKey = nil
    }

    public var nowSession: WatchSessionSummary? {
        let scoped = scopedSessions
        if let focusedSessionKey, let match = scoped.first(where: { $0.key == focusedSessionKey }) {
            return match
        }
        return WatchNowSession.preferred(from: scoped)
    }

    public var canStopNow: Bool {
        guard let session = nowSession else { return false }
        return activeRun(for: session) != nil
    }

    public func attach(link: any WatchCompanionLinking) {
        self.link = link
        refreshConnection()
    }

    public func beginConnecting() {
        state = .connecting
    }

    public func markUnavailable() {
        state = .unavailable
        sessions = []
        nowPreview = nil
        focusedSessionKey = nil
        activeRunBySession = [:]
    }

    public func refreshConnection() {
        guard let link else {
            state = .setupRequired
            return
        }
        guard link.isCompanionAvailable else {
            // Companion not installed: first-run copy stays truthful.
            state = .setupRequired
            servers = []
            sessions = []
            nowPreview = nil
            focusedSessionKey = nil
            activeRunBySession = [:]
            return
        }
        guard link.isReachable else {
            // Companion is installed but momentarily unreachable. If we were
            // ready (or signed out), present an honest disconnected state — not
            // "Set up on iPhone" (the companion exists) and not a stale ready
            // surface. If we never connected, stay on first-run copy.
            if state == .ready || state == .signedOut {
                markUnavailable()
            } else if state != .unavailable {
                state = .setupRequired
            }
            return
        }
        beginConnecting()
        let service = link.makeService()
        Task { await loadRegistry(using: service) }
    }

    /// Called by the app when WCSession reports the phone became reachable.
    /// Re-attaches and reloads the registry so a reconnect after backgrounding
    /// (or a quiet phone waking up) refreshes the wrist instead of staying stale.
    public func handleCompanionReachable() {
        refreshConnection()
    }

    /// Called by the app when WCSession reports the phone became unreachable.
    /// If we were ready, present an honest disconnected state so the wrist and
    /// complications stop claiming a live connection; do not lie that setup is
    /// missing — the companion is installed, just momentarily quiet.
    public func handleCompanionUnreachable() {
        guard let link, link.isCompanionAvailable else {
            if state != .setupRequired { state = .setupRequired }
            return
        }
        if state == .ready || state == .signedOut {
            markUnavailable()
        }
    }

    /// Pull-to-refresh from the Sessions list (and foreground): reload the
    /// registry first so an iPhone active-server switch is followed without a
    /// relaunch, then reload sessions for the adopted scope. An explicit
    /// `select(_:)` pin still wins — `loadRegistry` only re-adopts when the
    /// watch is following the phone or the pinned scope vanished.
    public func refreshFromList() async {
        guard let link else { return }
        await loadRegistry(using: link.makeService())
    }

    public func select(_ scope: ServerScope) async {
        followsPhoneActiveServer = false
        adopt(scope)
        await loadSessions()
    }

    public func focus(_ session: WatchSessionSummary) {
        focusedSessionKey = session.key
    }

    public func loadSessions() async {
        guard let link, let scope = selectedScope else { return }
        do {
            let snapshot = try await link.makeService().refreshSessions(
                scope: scope,
                collection: .current,
                query: nil,
                localLimit: 20
            )
            sessions = snapshot.value.items.filter { $0.key.scope == scope }
            dropRunsTheServerNoLongerReports()
            lastErrorCode = nil
            // A successful session load means we are genuinely ready: clear any
            // signed-out state a prior failed load may have set.
            if state == .signedOut { state = .ready }
            await refreshNowPreview()
        } catch WatchCompanionError.backend(.authRequired) {
            // The iPhone's session for this server is gone. The watch cannot
            // sign in, so present the truthful state instead of an empty ready
            // surface and disable mutations.
            state = .signedOut
            sessions = []
            nowPreview = nil
            focusedSessionKey = nil
            activeRunBySession = [:]
            lastErrorCode = "authRequired"
        } catch {
            lastErrorCode = "sessionsUnavailable"
        }
    }

    public func transcript(for session: WatchSessionSummary) async -> [WatchTranscriptBlock] {
        if let fixture = fixtureTranscriptBySessionID[session.key.sessionID] {
            return fixture
        }
        guard let link else { return [] }
        do {
            let snapshot = try await link.makeService().transcript(
                key: session.key,
                before: nil,
                limit: 20
            )
            return snapshot.value.blocks
        } catch {
            lastErrorCode = "transcriptUnavailable"
            return []
        }
    }

    public func send(text: String, to session: WatchSessionSummary) async -> RunKey? {
        await send(text: text, to: session.key)
    }

    public func sendVoiceNote(audio: Data, filename: String, to session: WatchSessionSummary) async -> RunKey? {
        await sendVoiceNote(audio: audio, filename: filename, to: session.key)
    }

    public func sendVoiceNote(audio: Data, filename: String, to key: SessionKey) async -> RunKey? {
        guard canMutate, let link, let scope = selectedScope else { return nil }
        do {
            let request = try WatchVoiceNoteRequest(
                scope: scope,
                expectedRevision: registryRevision,
                session: key,
                filename: filename,
                audio: audio
            )
            let receipt = try await link.sendVoiceNote(request)
            if let run = receipt.value {
                lastErrorCode = nil
                await loadSessions()
                activeRunBySession[key] = run
                markLocalRun(on: key)
                return run
            }
            lastErrorCode = "sendRejected"
            return nil
        } catch WatchVoiceNoteValidationError.audioTooLarge {
            lastErrorCode = "tooLarge"
            return nil
        } catch {
            lastErrorCode = "sendFailed"
            return nil
        }
    }

    public func send(text: String, to key: SessionKey) async -> RunKey? {
        guard canMutate, let link else { return nil }
        let created = Date()
        do {
            let context = try CommandContext(
                stableCommandID: CommandID(rawValue: UUID()),
                scope: key.scope,
                expectedRevision: registryRevision,
                createdAt: created,
                expiresAt: created.addingTimeInterval(60)
            )
            let receipt = await link.makeService().send(text: text, to: key, context: context)
            if let run = receipt.value {
                lastErrorCode = nil
                // Reload first: the optimistic run marker has to outlive the
                // reload, which drops runs the server reports as finished.
                await loadSessions()
                activeRunBySession[key] = run
                markLocalRun(on: key)
                return run
            }
            lastErrorCode = "sendRejected"
            return nil
        } catch {
            lastErrorCode = "sendFailed"
            return nil
        }
    }

    public func session(for key: SessionKey) -> WatchSessionSummary? {
        sessions.first(where: { $0.key == key })
    }

    public func createSession() async -> SessionKey? {
        guard canMutate, let scope = selectedScope else { return nil }
        guard let link else {
            return insertLocalSession(scope: scope, title: "New session")
        }
        let created = Date()
        do {
            let context = try CommandContext(
                stableCommandID: CommandID(rawValue: UUID()),
                scope: scope,
                expectedRevision: registryRevision,
                createdAt: created,
                expiresAt: created.addingTimeInterval(60)
            )
            let receipt = await link.makeService().createSession(
                scope: scope,
                profileID: nil,
                workspaceHandle: nil,
                context: context
            )
            guard let key = receipt.value else {
                lastErrorCode = "createRejected"
                return nil
            }
            focusedSessionKey = key
            lastErrorCode = nil
            await loadSessions()
            if session(for: key) == nil {
                _ = insertLocalSession(scope: scope, title: "New session", key: key)
            }
            return key
        } catch {
            lastErrorCode = "createFailed"
            return nil
        }
    }

    public func stop(_ session: WatchSessionSummary) async -> Bool {
        guard canMutate, let link, let run = activeRun(for: session) else { return false }
        let created = Date()
        do {
            let context = try CommandContext(
                stableCommandID: CommandID(rawValue: UUID()),
                scope: run.session.scope,
                expectedRevision: registryRevision,
                createdAt: created,
                expiresAt: created.addingTimeInterval(60)
            )
            let receipt = await link.makeService().stop(run: run, context: context)
            if receipt.value != nil {
                activeRunBySession[session.key] = nil
                lastErrorCode = nil
                await loadSessions()
                return true
            }
            lastErrorCode = "stopRejected"
            return false
        } catch {
            lastErrorCode = "stopFailed"
            return false
        }
    }

    public func activeRun(for session: WatchSessionSummary) -> RunKey? {
        activeRunBySession[session.key]
    }

    public func widgetSnapshot(observedAt: Date = Date()) -> RedactedWidgetSnapshot? {
        guard state == .ready, let scope = selectedScope else { return nil }
        let server = servers.first(where: { $0.scope == scope }) ?? servers.first
        guard let server else { return nil }
        let route: RedactedRoute
        if let nowSession {
            route = .session(nowSession.key)
        } else {
            route = .sessions(scope)
        }
        return try? RedactedWidgetSnapshot(
            scope: scope,
            displayName: server.displayName,
            activity: WatchNowSession.widgetActivity(from: scopedSessions),
            attentionCount: min(scopedSessions.filter(WatchNowSession.needsAttention).count, 999),
            observedAt: observedAt,
            route: route
        )
    }

    public var primaryMessage: String {
        switch state {
        case .setupRequired:
            return "Set up on iPhone"
        case .connecting:
            return "Connecting"
        case .unavailable:
            return "Hermex is unavailable"
        case .signedOut:
            return "Sign in on iPhone"
        case .ready:
            return servers.first?.displayName.rawValue ?? "Sessions"
        }
    }

    /// Mutations (create / send / stop / voice) are only allowed when the watch
    /// is genuinely ready: not connecting, not unreachable, and not signed out.
    public var canMutate: Bool {
        state == .ready
    }

    /// A short, user-facing explanation of the last failure so create / send /
    /// stop / transcript errors are not haptic-only. `nil` when there is nothing
    /// to surface.
    public var errorCopy: String? {
        guard let code = lastErrorCode else { return nil }
        switch code {
        case "authRequired":
            return "Sign in on iPhone to continue."
        case "sessionsUnavailable":
            return "Couldn’t load sessions. Try again."
        case "transcriptUnavailable":
            return "Couldn’t load the conversation."
        case "sendFailed":
            return "Couldn’t send. Try again."
        case "sendRejected":
            return "Hermex didn’t accept that message."
        case "createFailed":
            return "Couldn’t create a session. Try again."
        case "createRejected":
            return "Hermex didn’t create that session."
        case "stopFailed":
            return "Couldn’t stop the run."
        case "stopRejected":
            return "Hermex didn’t stop that run."
        default:
            return "Something went wrong. Try again."
        }
    }

    #if DEBUG
    /// Demo-only fixture for screenshot capture and UI tests. Wrapped in
    /// `DEBUG` so the demo strings ("Stand-up notes", etc.) never ship in the
    /// release module. UI tests opt in via the `HERMEX_WATCH_SCREENSHOT_FIXTURE`
    /// launch argument, which the app reads under its own `#if DEBUG` guard.
    public func applyScreenshotFixture() {
        let scope = ServerScope(
            epoch: InstallationEpoch(rawValue: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!),
            server: ServerID(rawValue: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!),
            generation: try! Generation(1)
        )
        let running = try! WatchSessionSummary(
            key: SessionKey(scope: scope, sessionID: "stand-up"),
            title: "Stand-up notes",
            profile: "default",
            workspaceLabel: nil,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_120),
            isPinned: false,
            isArchived: false,
            attention: false,
            runState: .responding
        )
        let pinned = try! WatchSessionSummary(
            key: SessionKey(scope: scope, sessionID: "weekend"),
            title: "Weekend plan",
            profile: "default",
            workspaceLabel: nil,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_080),
            isPinned: true,
            isArchived: false,
            attention: false,
            runState: nil
        )
        let attention = try! WatchSessionSummary(
            key: SessionKey(scope: scope, sessionID: "review"),
            title: "PR review",
            profile: nil,
            workspaceLabel: nil,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_040),
            isPinned: false,
            isArchived: false,
            attention: true,
            runState: .attention
        )
        applyReadyStateForTesting(
            servers: [RegistryEntry(scope: scope, displayName: try! RedactedDisplayName("Studio"))],
            sessions: [running, pinned, attention]
        )
        nowPreview = "Drafted the stand-up notes and queued the follow-ups."
        fixtureTranscriptBySessionID = [
            "stand-up": [
                .text(id: "1", role: .user, text: "Summarize stand-up."),
                .text(id: "2", role: .assistant, text: "Drafted the stand-up notes and queued the follow-ups."),
            ],
        ]
    }
    #endif

    @discardableResult
    private func insertLocalSession(
        scope: ServerScope,
        title: String,
        key: SessionKey? = nil
    ) -> SessionKey? {
        let resolvedKey: SessionKey
        if let key {
            resolvedKey = key
        } else if let created = try? SessionKey(
            scope: scope,
            sessionID: "local-\(UUID().uuidString.prefix(8))"
        ) {
            resolvedKey = created
        } else {
            return nil
        }
        guard let summary = try? WatchSessionSummary(
            key: resolvedKey,
            title: title,
            profile: nil,
            workspaceLabel: nil,
            updatedAt: Date(),
            isPinned: false,
            isArchived: false,
            attention: false,
            runState: nil
        ) else { return nil }
        sessions.insert(summary, at: 0)
        focusedSessionKey = resolvedKey
        nowPreview = WatchTranscriptPreview.lastAssistantText(
            in: fixtureTranscriptBySessionID[resolvedKey.sessionID] ?? []
        )
        lastErrorCode = nil
        return resolvedKey
    }

    func applyReadyStateForTesting(
        servers: [RegistryEntry],
        sessions: [WatchSessionSummary],
        revision: Revision = Revision(1)
    ) {
        self.servers = servers
        self.sessions = sessions
        selectedScope = servers.first?.scope
        registryRevision = revision
        state = .ready
    }

    private func refreshNowPreview() async {
        guard let session = nowSession else {
            nowPreview = nil
            return
        }
        let blocks = await transcript(for: session)
        nowPreview = WatchTranscriptPreview.lastAssistantText(in: blocks)
    }

    private func loadRegistry(using service: any WatchCompanionServicing) async {
        let snapshot = await service.registry()
        servers = snapshot.entries
        registryRevision = snapshot.revision
        if snapshot.entries.isEmpty {
            state = .setupRequired
            adopt(nil)
            return
        }
        // The iPhone lists its active server first. A selection that is gone from
        // the registry is always replaced; an unpinned watch also follows the
        // iPhone when it switches servers, so the wrist never operates on a
        // server the phone left behind.
        let preferred = snapshot.entries.first?.scope
        let selectionIsStale = snapshot.entries.contains(where: { $0.scope == selectedScope }) == false
        if selectionIsStale || (followsPhoneActiveServer && preferred != selectedScope) {
            adopt(preferred)
        }
        state = .ready
        await loadSessions()
    }

    private func adopt(_ scope: ServerScope?) {
        selectedScope = scope
        sessions = []
        nowPreview = nil
        focusedSessionKey = nil
        activeRunBySession = [:]
    }

    /// Keeps Stop honest: a run the server no longer reports as active is not
    /// stoppable, and a session that fell out of the current page cannot be shown.
    private func dropRunsTheServerNoLongerReports() {
        for key in Array(activeRunBySession.keys) {
            let isRunning = sessions.first(where: { $0.key == key })
                .map { WatchNowSession.isRunning($0.runState) } ?? false
            if !isRunning {
                activeRunBySession[key] = nil
            }
        }
    }

    private var scopedSessions: [WatchSessionSummary] {
        guard let selectedScope else { return sessions }
        return sessions.filter { $0.key.scope == selectedScope }
    }

    private func markLocalRun(on key: SessionKey) {
        guard let index = sessions.firstIndex(where: { $0.key == key }) else { return }
        let current = sessions[index]
        guard !WatchNowSession.isRunning(current.runState) else { return }
        guard let updated = try? WatchSessionSummary(
            key: current.key,
            title: current.title,
            profile: current.profile,
            workspaceLabel: current.workspaceLabel,
            updatedAt: current.updatedAt,
            isPinned: current.isPinned,
            isArchived: current.isArchived,
            attention: current.attention,
            runState: .responding
        ) else { return }
        sessions[index] = updated
    }

    func attachLinkWithoutRefreshingForTesting(_ link: any WatchCompanionLinking) {
        self.link = link
    }

    /// Awaitable stand-in for the `Task` that `refreshConnection()` spawns.
    func reloadRegistryForTesting() async {
        guard let link else { return }
        await loadRegistry(using: link.makeService())
    }
}
