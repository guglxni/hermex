import Foundation

/// Watch-side `WatchCompanionServicing` that talks only through a wire transport.
public struct WatchWireClient: WatchCompanionServicing, Sendable {
    private let transport: any WatchWireTransporting
    private let now: @Sendable () -> Date

    public init(transport: any WatchWireTransporting, now: @escaping @Sendable () -> Date = { Date() }) {
        self.transport = transport
        self.now = now
    }

    public func registry() async -> RegistrySnapshot {
        do {
            if case .registry(let snapshot) = try await transport.send(.registry) {
                return snapshot
            }
        } catch {}
        return emptyRegistry()
    }

    public func refreshSessions(
        scope: ServerScope,
        collection: SessionCollection,
        query: String?,
        localLimit: Int
    ) async throws -> ScopedSnapshot<BoundedCollection<WatchSessionSummary>> {
        try await read(
            scope: scope,
            operation: .sessions(scope: scope, collection: collection, query: query, localLimit: localLimit)
        )
    }

    public func transcript(
        key: SessionKey,
        before: Int?,
        limit: Int
    ) async throws -> ScopedSnapshot<WatchTranscript> {
        try await read(scope: key.scope, operation: .transcript(session: key, before: before, limit: limit))
    }

    public func createSession(
        scope: ServerScope,
        profileID: ProfileID?,
        workspaceHandle: WorkspaceHandle?,
        context: CommandContext
    ) async -> CommandReceipt<SessionKey> {
        await mutate(WatchMutationOperation.createSession(
            scope: scope,
            profileID: profileID,
            workspaceHandle: workspaceHandle
        ), context: context)
    }

    public func send(text: String, to key: SessionKey, context: CommandContext) async -> CommandReceipt<RunKey> {
        await mutate(.send(session: key, text: text), context: context)
    }

    public func events(for run: RunKey, afterEventID: String?) -> AsyncThrowingStream<WatchRunEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let envelope = try WatchRequestEnvelope.stream(
                        requestID: UUID(),
                        scope: run.session.scope,
                        operation: .run(run, afterEventID: afterEventID),
                        createdAt: now(),
                        expiresAt: now().addingTimeInterval(30)
                    )
                    let reply = try await transport.send(.request(envelope))
                    guard case .envelope(let response) = reply else {
                        continuation.finish(throwing: WatchCompanionError.backend(.invalidResponse))
                        return
                    }
                    try response.validate(against: envelope, receivedAt: now())
                    if case .runEvent(let event) = response.result {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func reconcile(run: RunKey) async throws -> ScopedSnapshot<WatchRunState> {
        try await read(scope: run.session.scope, operation: .runState(run: run))
    }

    public func stop(run: RunKey, context: CommandContext) async -> CommandReceipt<EmptyValue> {
        await mutate(.stop(run: run), context: context)
    }

    public func sendVoiceNote(_ request: WatchVoiceNoteRequest) async throws -> CommandReceipt<RunKey> {
        try await startedRun(from: .transcribe(request))
    }

    public func sendPhoto(_ request: WatchPhotoSendRequest) async throws -> CommandReceipt<RunKey> {
        try await startedRun(from: .sendPhoto(request))
    }

    public func composerOptions(scope: ServerScope) async throws -> ScopedSnapshot<WatchComposerOptions> {
        throw WatchCompanionError.unsupported(.composerOptions)
    }
    public func pendingApprovalHead(session: SessionKey) async throws -> ScopedSnapshot<WatchAttentionHead<WatchApproval>> {
        throw WatchCompanionError.unsupported(.pendingApprovalHead)
    }
    public func pendingClarificationHead(session: SessionKey) async throws -> ScopedSnapshot<WatchAttentionHead<WatchClarification>> {
        throw WatchCompanionError.unsupported(.pendingClarificationHead)
    }
    public func tasks(scope: ServerScope, localLimit: Int) async throws -> ScopedSnapshot<BoundedCollection<WatchTaskSummary>> {
        throw WatchCompanionError.unsupported(.tasks)
    }
    public func taskRuns(key: TaskKey, page: PageRequest) async throws -> ScopedSnapshot<BoundedPage<WatchTaskRun>> {
        throw WatchCompanionError.unsupported(.taskRuns)
    }
    public func taskRunDetail(key: TaskKey, runID: String) async throws -> ScopedSnapshot<WatchTaskRunDetail> {
        throw WatchCompanionError.unsupported(.taskRunDetail)
    }
    public func controlTask(key: TaskKey, action: TaskControl, context: CommandContext) async -> CommandReceipt<EmptyValue> {
        currentPinRejection(context: context, kind: .controlTask)
    }
    public func skills(scope: ServerScope, query: String?, localLimit: Int) async throws -> ScopedSnapshot<BoundedCollection<WatchSkillSummary>> {
        throw WatchCompanionError.unsupported(.skills)
    }
    public func skillDetail(key: SkillKey) async throws -> ScopedSnapshot<WatchSkillDetail> {
        throw WatchCompanionError.unsupported(.skillDetail)
    }
    public func skillContent(key: SkillKey, fileHandle: PathHandle?) async throws -> ScopedSnapshot<WatchSkillContent> {
        throw WatchCompanionError.unsupported(.skillContent)
    }
    public func memoryDocument(scope: ServerScope) async throws -> ScopedSnapshot<WatchMemoryDocument> {
        throw WatchCompanionError.unsupported(.memoryDocument)
    }
    public func insightsAggregate(scope: ServerScope, days: InsightsDays) async throws -> ScopedSnapshot<WatchInsightsAggregate> {
        throw WatchCompanionError.unsupported(.insightsAggregate)
    }
    public func workspace(session: SessionKey, parentPathHandle: PathHandle?) async throws -> ScopedSnapshot<BoundedCollection<WatchWorkspaceEntry>> {
        throw WatchCompanionError.unsupported(.workspace)
    }
    public func filePreview(session: SessionKey, pathHandle: PathHandle) async throws -> ScopedSnapshot<WatchFilePreview> {
        throw WatchCompanionError.unsupported(.filePreview)
    }
    public func gitAggregate(session: SessionKey) async throws -> ScopedSnapshot<WatchGitAggregate> {
        throw WatchCompanionError.unsupported(.gitAggregate)
    }
    public func diagnostics(scope: ServerScope) async throws -> ScopedSnapshot<WatchDiagnosticsProjection> {
        try await read(scope: scope, operation: .diagnostics(scope: scope))
    }
    public func media(_ descriptor: WatchMediaDescriptor) async throws -> WatchMediaPayload {
        try await read(scope: descriptor.scope, operation: .media(descriptor))
    }
    public func bots(scope: ServerScope) async throws -> ScopedSnapshot<[WatchBotSummary]> {
        throw WatchCompanionError.unsupported(.bots)
    }
    public func botConversation(key: BotKey) async throws -> ScopedSnapshot<WatchBotConversation> {
        throw WatchCompanionError.unsupported(.botConversation)
    }
    public func botEvents(for key: BotKey, replayEpoch: String?, afterSequence: Int?) -> AsyncThrowingStream<WatchBotEvent, Error> {
        AsyncThrowingStream { $0.finish(throwing: WatchCompanionError.unsupported(.botStream)) }
    }
    public func sendBot(text: String, to key: BotKey, context: CommandContext) async -> CommandReceipt<EmptyValue> {
        currentPinRejection(context: context, kind: .sendBot)
    }
    public func interruptBot(key: BotKey, context: CommandContext) async -> CommandReceipt<EmptyValue> {
        currentPinRejection(context: context, kind: .interruptBot)
    }

    private func read<Value>(scope: ServerScope, operation: WatchReadOperation) async throws -> Value {
        let envelope = try WatchRequestEnvelope.read(
            requestID: UUID(),
            scope: scope,
            operation: operation,
            createdAt: now(),
            expiresAt: now().addingTimeInterval(30)
        )
        let reply = try await transport.send(.request(envelope))
        guard case .envelope(let response) = reply else {
            throw failureAsError(reply)
        }
        // Correlate the reply with the request: request id, scope, operation
        // kind, and expiry must all line up so a stale or misrouted envelope
        // never populates watch state.
        try response.validate(against: envelope, receivedAt: now())
        switch (operation, response.result) {
        case (.sessions, .sessions(let value)):
            return try cast(value)
        case (.transcript, .transcript(let value)):
            return try cast(value)
        case (.runState, .runState(let value)):
            return try cast(value)
        case (.diagnostics, .diagnostics(let value)):
            return try cast(value)
        case (.media, .media(let value)):
            return try cast(value)
        default:
            throw WatchCompanionError.backend(.invalidResponse)
        }
    }

    private func startedRun(from message: WatchWireMessage) async throws -> CommandReceipt<RunKey> {
        let reply = try await transport.send(message)
        switch reply {
        case .startedRun(let receipt):
            return receipt
        case .failure:
            throw WatchCompanionError.backend(.invalidResponse)
        default:
            throw WatchCompanionError.backend(.invalidResponse)
        }
    }

    private func cast<T, Value>(_ value: T) throws -> Value {
        guard let typed = value as? Value else {
            throw WatchCompanionError.backend(.invalidResponse)
        }
        return typed
    }

    private func mutate<Value: Hashable & Codable & Sendable>(
        _ operation: WatchMutationOperation,
        context: CommandContext
    ) async -> CommandReceipt<Value> {
        do {
            let request = try WatchMutationRequest(
                requestID: UUID(),
                context: context,
                operation: operation,
                createdAt: context.createdAt,
                expiresAt: context.expiresAt
            )
            let reply = try await transport.send(.mutation(request))
            guard case .envelope(let response) = reply else {
                return currentPinRejection(context: context, kind: operation.kind)
            }
            // Enforce request-id / scope / operation / context correlation so a
            // mismatched or replayed envelope cannot be mistaken for this mutation.
            do {
                try response.validate(against: request, receivedAt: now())
            } catch {
                return currentPinRejection(context: context, kind: operation.kind)
            }
            switch response.result {
            case .createdSession(let receipt as CommandReceipt<Value>),
                 .startedRun(let receipt as CommandReceipt<Value>),
                 .mutation(let receipt as CommandReceipt<Value>):
                return receipt
            default:
                return currentPinRejection(context: context, kind: operation.kind)
            }
        } catch {
            return currentPinRejection(context: context, kind: operation.kind)
        }
    }

    private func currentPinRejection<Value: Hashable & Codable & Sendable>(
        context: CommandContext,
        kind: WatchOperationKind
    ) -> CommandReceipt<Value> {
        let receipt = try! MutationReceipt(
            context: context,
            operationKind: kind,
            phase: .rejected,
            updatedAt: context.createdAt,
            nonSecretResultID: "rejected"
        )
        return CommandReceipt(receipt: receipt, value: nil)
    }

    private func emptyRegistry() -> RegistrySnapshot {
        try! RegistrySnapshot(
            epoch: InstallationEpoch(rawValue: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))),
            revision: Revision(0),
            generatedAt: Date(timeIntervalSince1970: 1),
            entries: []
        )
    }

    /// Translates a non-envelope reply into the most specific watch error so the
    /// model can react: a 401 from the phone means the iPhone's session is gone
    /// and the user must sign in on iPhone; anything else is a generic backend
    /// failure.
    private func failureAsError(_ reply: WatchWireReply) -> Error {
        if case .failure(.rejected(let status, let code)) = reply, status == 401, code == "authRequired" {
            return WatchCompanionError.backend(.authRequired)
        }
        return WatchCompanionError.backend(.invalidResponse)
    }
}
