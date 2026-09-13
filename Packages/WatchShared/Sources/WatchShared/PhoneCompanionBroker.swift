import CryptoKit
import Foundation
import os

/// Maps watch operations onto a phone-owned backend. The watch never reaches
/// `hermes-webui`; this type is the iPhone-side `WatchCompanionServicing`.
public final class PhoneCompanionBroker: WatchCompanionServicing, @unchecked Sendable {
    private let epoch: InstallationEpoch
    private let backend: any WatchPhoneBackend
    private let now: @Sendable () -> Date
    private let storage: OSAllocatedUnfairLock<State>

    private struct State {
        var fence: ScopeFence
        var revision: UInt64
        var urlByServer: [ServerID: String]
        var generationByServer: [ServerID: UInt64]
        var lastSnapshot: RegistrySnapshot?
        var issuedRuns: [String: RunKey]
        var mediaByHandle: [String: CachedMedia]
    }

    private struct CachedMedia {
        let path: String
        let bytes: Data
    }

    public init(
        epoch: InstallationEpoch,
        backend: any WatchPhoneBackend,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.epoch = epoch
        self.backend = backend
        self.now = now
        self.storage = OSAllocatedUnfairLock(initialState: State(
            fence: ScopeFence(epoch: epoch),
            revision: 0,
            urlByServer: [:],
            generationByServer: [:],
            lastSnapshot: nil,
            issuedRuns: [:],
            mediaByHandle: [:]
        ))
    }

    public func registry() async -> RegistrySnapshot {
        let accounts = await backend.servers()
        return storage.withLock { state in
            var nextGenerations = state.generationByServer
            var urlByServer: [ServerID: String] = [:]
            var entries: [RegistryEntry] = []

            for account in accounts {
                let server = ServerID.derived(from: account.urlString)
                // A registry that lists one URL twice must not invalidate the whole
                // snapshot: keep the first entry, which is the phone's own order.
                guard urlByServer[server] == nil else { continue }
                let wasActive = state.fence.activeScopes[server] != nil
                let previous = nextGenerations[server] ?? 0
                let generationValue: UInt64
                if wasActive {
                    generationValue = previous == 0 ? 1 : previous
                } else if previous == 0 {
                    generationValue = 1
                } else if previous == UInt64.max {
                    continue
                } else {
                    generationValue = previous + 1
                }
                guard let generation = try? Generation(generationValue) else { continue }
                nextGenerations[server] = generationValue
                urlByServer[server] = account.urlString
                entries.append(RegistryEntry(
                    scope: ServerScope(epoch: epoch, server: server, generation: generation),
                    displayName: .sanitized(account.displayName)
                ))
            }

            if let lastSnapshot = state.lastSnapshot,
               registryIdentity(lastSnapshot.entries) == registryIdentity(entries) {
                return lastSnapshot
            }

            let snapshot = try? RegistrySnapshot(
                epoch: epoch,
                revision: Revision(state.revision + 1),
                generatedAt: now(),
                entries: entries
            )
            if let snapshot, (try? state.fence.apply(snapshot)) != nil {
                state.revision = snapshot.revision.rawValue
                state.urlByServer = urlByServer
                state.generationByServer = nextGenerations
                state.lastSnapshot = snapshot
                return snapshot
            }
            return state.lastSnapshot ?? fallbackEmptyRegistry(revision: state.revision)
        }
    }

    public func refreshSessions(
        scope: ServerScope,
        collection: SessionCollection,
        query: String?,
        localLimit: Int
    ) async throws -> ScopedSnapshot<BoundedCollection<WatchSessionSummary>> {
        let urlString = try resolvedURL(for: scope)
        let rows = try await backend.listSessions(
            urlString: urlString,
            archived: collection == .archived,
            query: query,
            limit: localLimit
        )
        let items = rows.compactMap { row -> WatchSessionSummary? in
            guard let key = try? SessionKey(scope: scope, sessionID: row.sessionID) else { return nil }
            return try? WatchSessionSummary(
                key: key,
                title: row.title,
                profile: row.profile,
                workspaceLabel: row.workspaceLabel,
                updatedAt: row.updatedAt,
                isPinned: row.isPinned,
                isArchived: row.isArchived,
                attention: row.attention,
                runState: row.runState
            )
        }
        let limited = Array(items.prefix(min(localLimit, 100)))
        return try scoped(
            scope,
            BoundedCollection(items: limited, isTruncated: items.count > limited.count, maximumItems: 100)
        )
    }

    public func transcript(
        key: SessionKey,
        before: Int?,
        limit: Int
    ) async throws -> ScopedSnapshot<WatchTranscript> {
        let urlString = try resolvedURL(for: key.scope)
        let page = try await backend.transcript(
            urlString: urlString,
            sessionID: key.sessionID,
            before: before,
            limit: limit
        )
        var projected: [WatchTranscriptBlock] = []
        var imagesProjected = 0
        for block in page.blocks.prefix(50) {
            guard projected.count < 50 else { break }
            switch block.kind {
            case .text(let role, let text):
                projected.append(.text(id: block.id, role: role, text: text))
            case .code(let language, let text, let isTruncated):
                projected.append(.code(id: block.id, language: language, text: text, isTruncated: isTruncated))
            case .tool(let title, let state, let summary):
                projected.append(.tool(id: block.id, title: title, state: state, summary: summary))
            case .image(let path, let mime, let alt):
                if imagesProjected < 4,
                   let path,
                   let image = await projectImage(
                    session: key,
                    urlString: urlString,
                    id: block.id,
                    path: path,
                    mime: mime,
                    alt: alt
                   ) {
                    projected.append(image)
                    imagesProjected += 1
                } else {
                    projected.append(
                        .unsupported(
                            id: block.id,
                            kind: "image",
                            summary: alt ?? "Image — open on iPhone"
                        )
                    )
                }
            case .unsupported(let kind, let summary):
                projected.append(.unsupported(id: block.id, kind: kind, summary: summary))
            }
        }
        return try scoped(
            key.scope,
            WatchTranscript(
                session: key,
                blocks: projected,
                nextBefore: page.nextBefore,
                isTruncated: page.isTruncated || page.blocks.count > 50
            )
        )
    }

    public func createSession(
        scope: ServerScope,
        profileID: ProfileID?,
        workspaceHandle: WorkspaceHandle?,
        context: CommandContext
    ) async -> CommandReceipt<SessionKey> {
        guard WatchMutationOperation.currentlyEnabledKinds.contains(.createSession) else {
            return rejected(context, kind: .createSession)
        }
        guard let urlString = try? resolvedURL(for: scope), matchesRevision(context) else {
            return rejected(context, kind: .createSession)
        }
        do {
            let sessionID = try await backend.createSession(
                urlString: urlString,
                profileID: profileID?.rawValue,
                workspace: workspaceHandle?.rawValue
            )
            let key = try SessionKey(scope: scope, sessionID: sessionID)
            let receipt = try MutationReceipt(
                context: context,
                operationKind: .createSession,
                phase: .acknowledged,
                updatedAt: now(),
                nonSecretResultID: sessionID
            )
            return CommandReceipt(receipt: receipt, value: key)
        } catch {
            return rejected(context, kind: .createSession)
        }
    }

    public func send(text: String, to key: SessionKey, context: CommandContext) async -> CommandReceipt<RunKey> {
        guard WatchMutationOperation.currentlyEnabledKinds.contains(.send) else {
            return rejected(context, kind: .send)
        }
        guard let urlString = try? resolvedURL(for: key.scope), matchesRevision(context) else {
            return rejected(context, kind: .send)
        }
        do {
            let streamID = try await backend.startChat(
                urlString: urlString,
                sessionID: key.sessionID,
                message: text,
                attachments: nil
            )
            let run = try RunKey(session: key, streamID: streamID)
            recordIssuedRun(run)
            let receipt = try MutationReceipt(
                context: context,
                operationKind: .send,
                phase: .acknowledged,
                updatedAt: now(),
                nonSecretResultID: streamID
            )
            return CommandReceipt(receipt: receipt, value: run)
        } catch {
            return rejected(context, kind: .send)
        }
    }

    public func events(for run: RunKey, afterEventID: String?) -> AsyncThrowingStream<WatchRunEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let urlString = try resolvedURL(for: run.session.scope)
                    let status = try await backend.runPhase(
                        urlString: urlString,
                        sessionID: run.session.sessionID,
                        streamID: run.streamID
                    )
                    let event = try WatchRunEvent(
                        key: run,
                        eventID: afterEventID.map { "\($0)-next" } ?? "0",
                        sequence: 0,
                        phase: status.phase,
                        textDelta: nil,
                        terminal: status.isTerminal
                    )
                    continuation.yield(event)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func reconcile(run: RunKey) async throws -> ScopedSnapshot<WatchRunState> {
        let urlString = try resolvedURL(for: run.session.scope)
        let status = try await backend.runPhase(
            urlString: urlString,
            sessionID: run.session.sessionID,
            streamID: run.streamID
        )
        return try scoped(
            run.session.scope,
            WatchRunState(
                key: run,
                phase: status.phase,
                lastEventID: nil,
                lastSequence: nil,
                isTerminal: status.isTerminal,
                summary: nil
            )
        )
    }

    /// Transcribe → upload → start chat with the bare transcript and the clip,
    /// matching iOS `ChatViewModel.sendVoiceNote`. Failure at any step rejects
    /// so the watch never claims a send that did not start.
    public func sendVoiceNote(_ request: WatchVoiceNoteRequest) async -> CommandReceipt<RunKey> {
        let context = voiceNoteContext(for: request)
        guard WatchMutationOperation.currentlyEnabledKinds.contains(.send) else {
            return rejected(context, kind: .send)
        }
        guard request.session.scope == request.scope,
              let urlString = try? resolvedURL(for: request.scope),
              matchesRevision(request.expectedRevision)
        else {
            return rejected(context, kind: .send)
        }
        do {
            let transcript = try await backend.transcribeAudio(
                urlString: urlString,
                data: request.audio,
                filename: request.filename
            )
            let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return rejected(context, kind: .send)
            }
            let uploaded = try await backend.uploadFile(
                urlString: urlString,
                sessionID: request.session.sessionID,
                data: request.audio,
                filename: request.filename
            )
            let streamID = try await backend.startChat(
                urlString: urlString,
                sessionID: request.session.sessionID,
                message: trimmed,
                attachments: [uploaded]
            )
            let run = try RunKey(session: request.session, streamID: streamID)
            recordIssuedRun(run)
            let receipt = try MutationReceipt(
                context: context,
                operationKind: .send,
                phase: .acknowledged,
                updatedAt: now(),
                nonSecretResultID: streamID
            )
            return CommandReceipt(receipt: receipt, value: run)
        } catch {
            return rejected(context, kind: .send)
        }
    }

    /// Upload a watch photo and start chat on the same composer attachment path.
    public func sendPhoto(_ request: WatchPhotoSendRequest) async -> CommandReceipt<RunKey> {
        let context = photoContext(for: request)
        guard WatchMutationOperation.currentlyEnabledKinds.contains(.send) else {
            return rejected(context, kind: .send)
        }
        guard request.session.scope == request.scope,
              let urlString = try? resolvedURL(for: request.scope),
              matchesRevision(request.expectedRevision)
        else {
            return rejected(context, kind: .send)
        }
        do {
            let uploaded = try await backend.uploadFile(
                urlString: urlString,
                sessionID: request.session.sessionID,
                data: request.image,
                filename: request.filename
            )
            let message = WatchTranscriptProjection.chatMessageText(
                draft: request.caption,
                attachments: [uploaded]
            )
            let streamID = try await backend.startChat(
                urlString: urlString,
                sessionID: request.session.sessionID,
                message: message,
                attachments: [uploaded]
            )
            let run = try RunKey(session: request.session, streamID: streamID)
            recordIssuedRun(run)
            let receipt = try MutationReceipt(
                context: context,
                operationKind: .send,
                phase: .acknowledged,
                updatedAt: now(),
                nonSecretResultID: streamID
            )
            return CommandReceipt(receipt: receipt, value: run)
        } catch {
            return rejected(context, kind: .send)
        }
    }

    public func transcribeVoiceNote(_ request: WatchVoiceNoteRequest) async throws -> String {
        guard let urlString = try? resolvedURL(for: request.scope),
              matchesRevision(request.expectedRevision)
        else {
            throw WatchCompanionError.scopeRejected
        }
        return try await backend.transcribeAudio(
            urlString: urlString,
            data: request.audio,
            filename: request.filename
        )
    }

    private func photoContext(for request: WatchPhotoSendRequest) -> CommandContext {
        let created = now()
        return try! CommandContext(
            stableCommandID: CommandID(rawValue: UUID()),
            scope: request.scope,
            expectedRevision: request.expectedRevision,
            createdAt: created,
            expiresAt: created.addingTimeInterval(60)
        )
    }

    private func voiceNoteContext(for request: WatchVoiceNoteRequest) -> CommandContext {
        let created = now()
        return try! CommandContext(
            stableCommandID: CommandID(rawValue: UUID()),
            scope: request.scope,
            expectedRevision: request.expectedRevision,
            createdAt: created,
            expiresAt: created.addingTimeInterval(60)
        )
    }

    public func stop(run: RunKey, context: CommandContext) async -> CommandReceipt<EmptyValue> {
        guard WatchMutationOperation.currentlyEnabledKinds.contains(.stop) else {
            return rejected(context, kind: .stop)
        }
        guard let urlString = try? resolvedURL(for: run.session.scope), matchesRevision(context) else {
            return rejected(context, kind: .stop)
        }
        guard consumeIssuedRun(run) else {
            return rejected(context, kind: .stop)
        }
        do {
            try await backend.cancelChat(urlString: urlString, streamID: run.streamID)
            let receipt = try MutationReceipt(
                context: context,
                operationKind: .stop,
                phase: .acknowledged,
                updatedAt: now(),
                nonSecretResultID: run.streamID
            )
            return CommandReceipt(receipt: receipt, value: EmptyValue())
        } catch {
            recordIssuedRun(run)
            return rejected(context, kind: .stop)
        }
    }

    public func composerOptions(scope: ServerScope) async throws -> ScopedSnapshot<WatchComposerOptions> {
        throw WatchCompanionError.unsupported(.composerOptions)
    }

    public func pendingApprovalHead(
        session: SessionKey
    ) async throws -> ScopedSnapshot<WatchAttentionHead<WatchApproval>> {
        throw WatchCompanionError.unsupported(.pendingApprovalHead)
    }

    public func pendingClarificationHead(
        session: SessionKey
    ) async throws -> ScopedSnapshot<WatchAttentionHead<WatchClarification>> {
        throw WatchCompanionError.unsupported(.pendingClarificationHead)
    }

    public func tasks(
        scope: ServerScope,
        localLimit: Int
    ) async throws -> ScopedSnapshot<BoundedCollection<WatchTaskSummary>> {
        throw WatchCompanionError.unsupported(.tasks)
    }

    public func taskRuns(
        key: TaskKey,
        page: PageRequest
    ) async throws -> ScopedSnapshot<BoundedPage<WatchTaskRun>> {
        throw WatchCompanionError.unsupported(.taskRuns)
    }

    public func taskRunDetail(key: TaskKey, runID: String) async throws -> ScopedSnapshot<WatchTaskRunDetail> {
        throw WatchCompanionError.unsupported(.taskRunDetail)
    }

    public func controlTask(
        key: TaskKey,
        action: TaskControl,
        context: CommandContext
    ) async -> CommandReceipt<EmptyValue> {
        rejected(context, kind: .controlTask)
    }

    public func skills(
        scope: ServerScope,
        query: String?,
        localLimit: Int
    ) async throws -> ScopedSnapshot<BoundedCollection<WatchSkillSummary>> {
        throw WatchCompanionError.unsupported(.skills)
    }

    public func skillDetail(key: SkillKey) async throws -> ScopedSnapshot<WatchSkillDetail> {
        throw WatchCompanionError.unsupported(.skillDetail)
    }

    public func skillContent(
        key: SkillKey,
        fileHandle: PathHandle?
    ) async throws -> ScopedSnapshot<WatchSkillContent> {
        throw WatchCompanionError.unsupported(.skillContent)
    }

    public func memoryDocument(scope: ServerScope) async throws -> ScopedSnapshot<WatchMemoryDocument> {
        throw WatchCompanionError.unsupported(.memoryDocument)
    }

    public func insightsAggregate(
        scope: ServerScope,
        days: InsightsDays
    ) async throws -> ScopedSnapshot<WatchInsightsAggregate> {
        throw WatchCompanionError.unsupported(.insightsAggregate)
    }

    public func workspace(
        session: SessionKey,
        parentPathHandle: PathHandle?
    ) async throws -> ScopedSnapshot<BoundedCollection<WatchWorkspaceEntry>> {
        throw WatchCompanionError.unsupported(.workspace)
    }

    public func filePreview(
        session: SessionKey,
        pathHandle: PathHandle
    ) async throws -> ScopedSnapshot<WatchFilePreview> {
        throw WatchCompanionError.unsupported(.filePreview)
    }

    public func gitAggregate(session: SessionKey) async throws -> ScopedSnapshot<WatchGitAggregate> {
        throw WatchCompanionError.unsupported(.gitAggregate)
    }

    public func diagnostics(scope: ServerScope) async throws -> ScopedSnapshot<WatchDiagnosticsProjection> {
        let observed = now()
        return try scoped(
            scope,
            WatchDiagnosticsProjection(
                scope: scope,
                source: .phoneBroker,
                observedAt: observed,
                expiresAt: observed.addingTimeInterval(30),
                codes: storage.withLock { $0.fence.decision(for: scope) == .accept ? [] : [.routeUnavailable] }
            )
        )
    }

    public func media(_ descriptor: WatchMediaDescriptor) async throws -> WatchMediaPayload {
        let urlString = try resolvedURL(for: descriptor.scope)
        if let cached = storage.withLock({ $0.mediaByHandle[descriptor.handle.rawValue] }),
           cached.bytes.count == descriptor.byteSize {
            return try WatchMediaPayload(descriptor: descriptor, bytes: cached.bytes)
        }
        let path = storage.withLock({ $0.mediaByHandle[descriptor.handle.rawValue]?.path })
            ?? descriptor.handle.rawValue
        let raw = try await backend.mediaData(
            urlString: urlString,
            sessionID: descriptor.session.sessionID,
            path: path
        )
        guard let bytes = WatchImageThumbnail.jpeg(from: raw) ?? (raw.count <= WatchImageThumbnail.watchFaceMaxBytes ? raw : nil) else {
            throw WatchCompanionError.backend(.invalidResponse)
        }
        cacheMedia(handle: descriptor.handle.rawValue, path: path, bytes: bytes)
        return try WatchMediaPayload(descriptor: descriptor, bytes: bytes)
    }

    public func bots(scope: ServerScope) async throws -> ScopedSnapshot<[WatchBotSummary]> {
        throw WatchCompanionError.unsupported(.bots)
    }

    public func botConversation(key: BotKey) async throws -> ScopedSnapshot<WatchBotConversation> {
        throw WatchCompanionError.unsupported(.botConversation)
    }

    public func botEvents(
        for key: BotKey,
        replayEpoch: String?,
        afterSequence: Int?
    ) -> AsyncThrowingStream<WatchBotEvent, Error> {
        AsyncThrowingStream { $0.finish(throwing: WatchCompanionError.unsupported(.botStream)) }
    }

    public func sendBot(text: String, to key: BotKey, context: CommandContext) async -> CommandReceipt<EmptyValue> {
        rejected(context, kind: .sendBot)
    }

    public func interruptBot(key: BotKey, context: CommandContext) async -> CommandReceipt<EmptyValue> {
        rejected(context, kind: .interruptBot)
    }

    private func projectImage(
        session: SessionKey,
        urlString: String,
        id: String,
        path: String,
        mime: String?,
        alt: String?
    ) async -> WatchTranscriptBlock? {
        guard !path.hasPrefix("http://"), !path.hasPrefix("https://") else { return nil }
        do {
            let raw = try await backend.mediaData(
                urlString: urlString,
                sessionID: session.sessionID,
                path: path
            )
            guard let bytes = WatchImageThumbnail.jpeg(from: raw) else { return nil }
            let handle = try mediaHandle(for: path)
            let observed = now()
            let digest = sha256Hex(bytes)
            let descriptor = try WatchMediaDescriptor(
                scope: session.scope,
                session: session,
                origin: OriginBinding(digest: sha256Hex(Data(path.utf8))),
                handle: handle,
                mimeType: "image/jpeg",
                byteSize: bytes.count,
                sha256: digest,
                observedAt: observed,
                expiresAt: observed.addingTimeInterval(120)
            )
            cacheMedia(handle: handle.rawValue, path: path, bytes: bytes)
            return .image(id: id, descriptor: descriptor, alt: alt)
        } catch {
            return nil
        }
    }

    private func mediaHandle(for path: String) throws -> MediaHandle {
        if path.utf8.count <= ContractLimits.identifierUTF8Bytes {
            return try MediaHandle(path)
        }
        return try MediaHandle(sha256Hex(Data(path.utf8)))
    }

    private func cacheMedia(handle: String, path: String, bytes: Data) {
        storage.withLock { state in
            if state.mediaByHandle.count >= 16 {
                state.mediaByHandle.removeAll()
            }
            state.mediaByHandle[handle] = CachedMedia(path: path, bytes: bytes)
        }
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func registryIdentity(_ entries: [RegistryEntry]) -> [String] {
        entries.map {
            "\($0.scope.server.rawValue.uuidString)|\($0.scope.generation.rawValue)|\($0.displayName.rawValue)"
        }
    }

    private func recordIssuedRun(_ run: RunKey) {
        storage.withLock { $0.issuedRuns[run.streamID] = run }
    }

    private func consumeIssuedRun(_ run: RunKey) -> Bool {
        storage.withLock { state in
            guard state.issuedRuns[run.streamID] == run else { return false }
            state.issuedRuns[run.streamID] = nil
            return true
        }
    }

    private func resolvedURL(for scope: ServerScope) throws -> String {
        try storage.withLock { state in
            guard state.fence.decision(for: scope) == .accept, let url = state.urlByServer[scope.server] else {
                throw WatchCompanionError.scopeRejected
            }
            return url
        }
    }

    private func matchesRevision(_ context: CommandContext) -> Bool {
        matchesRevision(context.expectedRevision)
    }

    private func matchesRevision(_ revision: Revision) -> Bool {
        storage.withLock { $0.fence.registryRevision == revision }
    }

    private func scoped<Value: Codable & Sendable>(_ scope: ServerScope, _ value: Value) throws -> ScopedSnapshot<Value> {
        let observed = now()
        let revision = storage.withLock { $0.fence.registryRevision }
        return try ScopedSnapshot(
            schema: 1,
            scope: scope,
            revision: revision,
            freshness: Freshness(
                observedAt: observed,
                expiresAt: observed.addingTimeInterval(30),
                source: .phoneProjection
            ),
            value: value
        )
    }

    private func rejected<Value: Hashable & Codable & Sendable>(
        _ context: CommandContext,
        kind: WatchOperationKind
    ) -> CommandReceipt<Value> {
        let receipt = try? MutationReceipt(
            context: context,
            operationKind: kind,
            phase: .rejected,
            updatedAt: now(),
            nonSecretResultID: "rejected"
        )
        if let receipt {
            return CommandReceipt(receipt: receipt, value: nil)
        }
        let fallback = try! MutationReceipt(
            context: context,
            operationKind: kind,
            phase: .rejected,
            updatedAt: context.createdAt,
            nonSecretResultID: "rejected"
        )
        return CommandReceipt(receipt: fallback, value: nil)
    }

    private func fallbackEmptyRegistry(revision: UInt64) -> RegistrySnapshot {
        try! RegistrySnapshot(
            epoch: epoch,
            revision: Revision(revision),
            generatedAt: Date(timeIntervalSince1970: 1),
            entries: []
        )
    }
}
