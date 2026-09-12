import Foundation
import Testing
@testable import WatchShared

@Suite struct ServiceBoundaryTests {
    private final class CurrentPinService: WatchCompanionServicing, @unchecked Sendable {
        private(set) var sideEffects: [String] = []
        func registry() async -> RegistrySnapshot { fatalError("unused") }
        func refreshSessions(scope: ServerScope, collection: SessionCollection, query: String?, localLimit: Int) async throws -> ScopedSnapshot<BoundedCollection<WatchSessionSummary>> { fatalError("unused") }
        func composerOptions(scope: ServerScope) async throws -> ScopedSnapshot<WatchComposerOptions> { fatalError("unused") }
        func transcript(key: SessionKey, before: Int?, limit: Int) async throws -> ScopedSnapshot<WatchTranscript> { fatalError("unused") }
        func createSession(scope: ServerScope, profileID: ProfileID?, workspaceHandle: WorkspaceHandle?, context: CommandContext) async -> CommandReceipt<SessionKey> { fatalError("unused") }
        func send(text: String, to key: SessionKey, context: CommandContext) async -> CommandReceipt<RunKey> { fatalError("unused") }
        func events(for run: RunKey, afterEventID: String?) -> AsyncThrowingStream<WatchRunEvent, Error> { fatalError("unused") }
        func reconcile(run: RunKey) async throws -> ScopedSnapshot<WatchRunState> { fatalError("unused") }
        func stop(run: RunKey, context: CommandContext) async -> CommandReceipt<EmptyValue> { fatalError("unused") }
        func pendingApprovalHead(session: SessionKey) async throws -> ScopedSnapshot<WatchAttentionHead<WatchApproval>> { fatalError("unused") }
        func pendingClarificationHead(session: SessionKey) async throws -> ScopedSnapshot<WatchAttentionHead<WatchClarification>> { fatalError("unused") }
        func tasks(scope: ServerScope, localLimit: Int) async throws -> ScopedSnapshot<BoundedCollection<WatchTaskSummary>> { fatalError("unused") }
        func taskRuns(key: TaskKey, page: PageRequest) async throws -> ScopedSnapshot<BoundedPage<WatchTaskRun>> { fatalError("unused") }
        func taskRunDetail(key: TaskKey, runID: String) async throws -> ScopedSnapshot<WatchTaskRunDetail> { fatalError("unused") }
        func controlTask(key: TaskKey, action: TaskControl, context: CommandContext) async -> CommandReceipt<EmptyValue> { fatalError("unused") }
        func skills(scope: ServerScope, query: String?, localLimit: Int) async throws -> ScopedSnapshot<BoundedCollection<WatchSkillSummary>> { fatalError("unused") }
        func skillDetail(key: SkillKey) async throws -> ScopedSnapshot<WatchSkillDetail> { fatalError("unused") }
        func skillContent(key: SkillKey, fileHandle: PathHandle?) async throws -> ScopedSnapshot<WatchSkillContent> { fatalError("unused") }
        func memoryDocument(scope: ServerScope) async throws -> ScopedSnapshot<WatchMemoryDocument> { fatalError("unused") }
        func insightsAggregate(scope: ServerScope, days: InsightsDays) async throws -> ScopedSnapshot<WatchInsightsAggregate> { fatalError("unused") }
        func workspace(session: SessionKey, parentPathHandle: PathHandle?) async throws -> ScopedSnapshot<BoundedCollection<WatchWorkspaceEntry>> { fatalError("unused") }
        func filePreview(session: SessionKey, pathHandle: PathHandle) async throws -> ScopedSnapshot<WatchFilePreview> { fatalError("unused") }
        func gitAggregate(session: SessionKey) async throws -> ScopedSnapshot<WatchGitAggregate> { fatalError("unused") }
        func diagnostics(scope: ServerScope) async throws -> ScopedSnapshot<WatchDiagnosticsProjection> { fatalError("unused") }
        func media(_ descriptor: WatchMediaDescriptor) async throws -> WatchMediaPayload { fatalError("unused") }
        func bots(scope: ServerScope) async throws -> ScopedSnapshot<[WatchBotSummary]> { fatalError("unused") }
        func botConversation(key: BotKey) async throws -> ScopedSnapshot<WatchBotConversation> { fatalError("unused") }
        func botEvents(for key: BotKey, replayEpoch: String?, afterSequence: Int?) -> AsyncThrowingStream<WatchBotEvent, Error> { fatalError("unused") }
        func sendBot(text: String, to key: BotKey, context: CommandContext) async -> CommandReceipt<EmptyValue> { fatalError("unused") }
        func interruptBot(key: BotKey, context: CommandContext) async -> CommandReceipt<EmptyValue> { fatalError("unused") }
    }

    private func fixture() throws -> (ApprovalKey, ClarificationKey, CommandContext) {
        let scope = ServerScope(epoch: InstallationEpoch(rawValue: UUID()), server: ServerID(rawValue: UUID()), generation: try Generation(1))
        let session = try SessionKey(scope: scope, sessionID: "session")
        let created = Date(timeIntervalSinceReferenceDate: 100)
        let context = try CommandContext(stableCommandID: CommandID(rawValue: UUID()), scope: scope, expectedRevision: Revision(7), createdAt: created, expiresAt: created.addingTimeInterval(60))
        return (try ApprovalKey(session: session, remoteID: "approval"), try ClarificationKey(session: session, remoteID: "clarification"), context)
    }

    @Test func frozenFacadeProvidesExactCurrentPinAttentionRejections() async throws {
        let service = CurrentPinService()
        let (approval, clarification, context) = try fixture()
        let approvalReceipt = await service.respond(approval: approval, choice: .once, context: context)
        let clarificationReceipt = await service.respond(clarification: clarification, answer: "answer", context: context)
        #expect(approvalReceipt.receipt.context == context)
        #expect(approvalReceipt.receipt.operationKind == .respondApproval)
        #expect(approvalReceipt.receipt.phase == .rejected)
        #expect(approvalReceipt.receipt.nonSecretResultID == "attentionExactIDUnavailable")
        #expect(clarificationReceipt.receipt.context == context)
        #expect(clarificationReceipt.receipt.operationKind == .respondClarification)
        #expect(clarificationReceipt.receipt.phase == .rejected)
        #expect(clarificationReceipt.receipt.nonSecretResultID == "attentionExactIDUnavailable")
        #expect(service.sideEffects.isEmpty)
        #expect(!WatchMutationOperation.currentlyEnabledKinds.contains(.respondApproval))
        #expect(!WatchMutationOperation.currentlyEnabledKinds.contains(.respondClarification))
    }

    @Test func serviceProtocolIsPublicSendableAndSolelyOwned() throws {
        let _: any Sendable.Type = (any WatchCompanionServicing).self
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/WatchShared")
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter { $0.pathExtension == "swift" }
        let owners = try files.filter { try String(contentsOf: $0, encoding: .utf8).contains("protocol WatchCompanionServicing") }
        #expect(owners.map(\.lastPathComponent) == ["ServiceBoundary.swift"])
    }
}
