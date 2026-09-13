import Foundation

public struct WatchWireDispatcher: Sendable {
    public typealias VoiceNoteHandler = @Sendable (WatchVoiceNoteRequest) async -> CommandReceipt<RunKey>

    private let service: any WatchCompanionServicing
    private let transcribe: VoiceNoteHandler?

    public init(service: any WatchCompanionServicing, transcribe: VoiceNoteHandler? = nil) {
        self.service = service
        self.transcribe = transcribe
    }

    public func handle(_ message: WatchWireMessage) async -> WatchWireReply {
        switch message {
        case .registry:
            return .registry(await service.registry())
        case .request(let envelope):
            return await handleRequest(envelope)
        case .mutation(let request):
            return await handleMutation(request)
        case .transcribe(let request):
            return await handleTranscribe(request)
        case .transcribeFile:
            return .failure(.rejected(status: 404, sanitizedCode: "transcribeFileUnresolved"))
        }
    }

    private func handleTranscribe(_ request: WatchVoiceNoteRequest) async -> WatchWireReply {
        guard let transcribe else {
            return .failure(.rejected(status: 404, sanitizedCode: "transcribeUnavailable"))
        }
        let receipt = await transcribe(request)
        guard receipt.receipt.phase == .acknowledged, receipt.value != nil else {
            return .failure(.uncertain(code: "transcribeFailed"))
        }
        return .startedRun(receipt)
    }

    private func handleRequest(_ envelope: WatchRequestEnvelope) async -> WatchWireReply {
        let kind: WatchOperationKind
        let scope: ServerScope
        let created: Date
        let expires: Date
        let requestID: UUID
        switch envelope {
        case .read(_, let id, let requestScope, let requestKind, let operation, let createdAt, let expiresAt):
            requestID = id
            scope = requestScope
            kind = requestKind
            created = createdAt
            expires = expiresAt
            do {
                let result = try await performRead(operation)
                let response = try WatchResponseEnvelope(
                    requestID: requestID,
                    scope: scope,
                    requestOperationKind: kind,
                    requestCreatedAt: created,
                    requestExpiresAt: expires,
                    commandContext: nil,
                    result: result
                )
                return .envelope(response)
            } catch WatchCompanionError.backend(.authRequired) {
                return .failure(.rejected(status: 401, sanitizedCode: "authRequired"))
            } catch {
                return .failure(.uncertain(code: "readFailed"))
            }
        case .stream(_, let id, let requestScope, let requestKind, let operation, let createdAt, let expiresAt):
            requestID = id
            scope = requestScope
            kind = requestKind
            created = createdAt
            expires = expiresAt
            do {
                let result = try await performStream(operation)
                let response = try WatchResponseEnvelope(
                    requestID: requestID,
                    scope: scope,
                    requestOperationKind: kind,
                    requestCreatedAt: created,
                    requestExpiresAt: expires,
                    commandContext: nil,
                    result: result
                )
                return .envelope(response)
            } catch {
                return .failure(.uncertain(code: "streamFailed"))
            }
        }
    }

    private func handleMutation(_ request: WatchMutationRequest) async -> WatchWireReply {
        let result: WatchOperationResult
        switch request.operation {
        case .createSession(let scope, let profileID, let workspaceHandle):
            result = .createdSession(await service.createSession(
                scope: scope,
                profileID: profileID,
                workspaceHandle: workspaceHandle,
                context: request.context
            ))
        case .send(let session, let text):
            result = .startedRun(await service.send(text: text, to: session, context: request.context))
        case .stop(let run):
            result = .mutation(await service.stop(run: run, context: request.context))
        case .controlTask(let key, let action):
            result = .mutation(await service.controlTask(key: key, action: action, context: request.context))
        case .sendBot(let bot, let text):
            result = .mutation(await service.sendBot(text: text, to: bot, context: request.context))
        case .interruptBot(let bot):
            result = .mutation(await service.interruptBot(key: bot, context: request.context))
        case .respondApproval, .respondClarification:
            return .failure(.rejected(status: 403, sanitizedCode: "attentionDisabled"))
        }
        do {
            let response = try WatchResponseEnvelope(
                requestID: request.requestID,
                scope: request.context.scope,
                requestOperationKind: request.operationKind,
                requestCreatedAt: request.createdAt,
                requestExpiresAt: request.expiresAt,
                commandContext: request.context,
                result: result
            )
            return .envelope(response)
        } catch {
            return .failure(.invalidEnvelope(code: "responseInvalid"))
        }
    }

    private func performRead(_ operation: WatchReadOperation) async throws -> WatchOperationResult {
        switch operation {
        case .sessions(let scope, let collection, let query, let limit):
            return .sessions(try await service.refreshSessions(
                scope: scope,
                collection: collection,
                query: query,
                localLimit: limit
            ))
        case .transcript(let session, let before, let limit):
            return .transcript(try await service.transcript(key: session, before: before, limit: limit))
        case .runState(let run):
            return .runState(try await service.reconcile(run: run))
        case .diagnostics(let scope):
            return .diagnostics(try await service.diagnostics(scope: scope))
        default:
            throw WatchCompanionError.unsupported(operation.kind)
        }
    }
    private func performStream(_ operation: WatchStreamOperation) async throws -> WatchOperationResult {
        switch operation {
        case .run(let run, let afterEventID):
            for try await event in service.events(for: run, afterEventID: afterEventID) {
                return .runEvent(event)
            }
            throw WatchCompanionError.backend(.invalidResponse)
        case .bot:
            throw WatchCompanionError.unsupported(.botStream)
        }
    }
}
