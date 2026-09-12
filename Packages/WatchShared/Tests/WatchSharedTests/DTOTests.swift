import Foundation
import Testing
@testable import WatchShared

@Suite struct DTOTests {
    private func scope() throws -> ServerScope { ServerScope(epoch: InstallationEpoch(rawValue: UUID()), server: ServerID(rawValue: UUID()), generation: try Generation(1)) }

    @Test func approvalChoicePreservesIterableCodableWireContract() throws {
        func requireCaseIterable<T: CaseIterable>(_: T.Type) {}
        requireCaseIterable(ApprovalChoice.self)

        let choices = ApprovalChoice.allCases
        #expect(choices.map(\.rawValue) == ["once", "session", "always", "deny"])
        #expect(try JSONDecoder().decode([ApprovalChoice].self, from: JSONEncoder().encode(choices)) == choices)
    }

    @Test func boundedContainersAndPageRequestsValidateAtInitAndDecode() throws {
        #expect(throws: (any Error).self) { try PageRequest(continuation: nil, limit: 0) }
        let page = try BoundedPage(items: [1, 2], continuation: "next", isTruncated: true, maximumItems: 2)
        #expect(try JSONDecoder().decode(BoundedPage<Int>.self, from: JSONEncoder().encode(page)) == page)
        #expect(throws: (any Error).self) { try BoundedCollection(items: [1, 2], isTruncated: false, maximumItems: 1) }
    }

    @Test func insightsDaysAndTextPayloadsRejectInvalidBounds() throws {
        #expect(try InsightsDays(365).value == 365)
        #expect(throws: (any Error).self) { try InsightsDays(0) }
        let scope = try scope(); let session = try SessionKey(scope: scope, sessionID: "s")
        #expect(throws: (any Error).self) { try WatchTranscript(session: session, blocks: [.text(id: "id", role: .user, text: String(repeating: "x", count: 16_385))], nextBefore: nil, isTruncated: false) }
    }

    @Test func attentionAndBotContractsPreserveRealRequestIdentity() throws {
        let projection = try WatchBotApprovalProjection(requestID: "request-1", choices: nil, redactedCommand: nil, toolName: nil, displaySummary: nil)
        #expect(projection.requestID == "request-1")
        #expect(throws: (any Error).self) { try WatchBotApprovalProjection(requestID: " ", choices: nil, redactedCommand: nil, toolName: nil, displaySummary: nil) }
        let clarification = try WatchBotClarificationProjection(requestID: "request-2", form: .open, displaySummary: nil)
        #expect(try JSONDecoder().decode(WatchBotClarificationProjection.self, from: JSONEncoder().encode(clarification)) == clarification)
    }

    private func replacing<T: Encodable>(_ value: T, _ key: String, with replacement: Any) throws -> Data {
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
        object[key] = replacement
        return try JSONSerialization.data(withJSONObject: object)
    }

    @Test func mediaDescriptorMalformedEncodedFixtureReentersValidation() throws {
        let scope = try scope(); let session = try SessionKey(scope: scope, sessionID: "s")
        let observed = Date(timeIntervalSinceReferenceDate: 100), expires = Date(timeIntervalSinceReferenceDate: 200)
        let descriptor = try WatchMediaDescriptor(scope: scope, session: session, origin: OriginBinding(digest: "sha256:origin"), handle: MediaHandle("m"), mimeType: "image/png", byteSize: 4, sha256: String(repeating: "a", count: 64), observedAt: observed, expiresAt: expires)
        #expect(try WatchMediaPayload(descriptor: descriptor, bytes: Data([1,2,3,4])).bytes.count == 4)
        #expect(throws: (any Error).self) { try WatchMediaPayload(descriptor: descriptor, bytes: Data([1])) }
        #expect(throws: (any Error).self) { try JSONDecoder().decode(WatchMediaDescriptor.self, from: replacing(descriptor, "byteSize", with: 1_048_577)) }
        #expect(throws: (any Error).self) { try JSONDecoder().decode(WatchMediaDescriptor.self, from: replacing(descriptor, "sha256", with: "bad")) }
        #expect(throws: (any Error).self) { try JSONDecoder().decode(WatchMediaDescriptor.self, from: replacing(descriptor, "expiresAt", with: observed.timeIntervalSinceReferenceDate)) }
    }

    @Test func alertProjectionMalformedEncodedFixtureReentersValidation() throws {
        let alertScope = try scope(), now = Date(timeIntervalSinceReferenceDate: 100)
        let alert = try WatchAlertProjection(scope: alertScope, alertID: UUID(), kind: .serverDisconnected, dedupeKey: "dedupe", source: .brokerSnapshot, observedAt: now, expiresAt: now.addingTimeInterval(60), route: .diagnostics(alertScope), genericTitleCode: "title", genericBodyCode: "body")
        #expect(try JSONDecoder().decode(WatchAlertProjection.self, from: JSONEncoder().encode(alert)) == alert)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(WatchAlertProjection.self, from: replacing(alert, "dedupeKey", with: " ")) }
        #expect(throws: (any Error).self) { try JSONDecoder().decode(WatchAlertProjection.self, from: replacing(alert, "expiresAt", with: now.timeIntervalSinceReferenceDate)) }
        let other = try scope()
        #expect(throws: (any Error).self) { try JSONDecoder().decode(WatchAlertProjection.self, from: replacing(alert, "route", with: try JSONSerialization.jsonObject(with: JSONEncoder().encode(WatchAlertRoute.diagnostics(other))))) }
    }

    @Test func allDTOFamiliesArePublicCodableSendableHashable() throws {
        func require<T: Codable & Sendable & Hashable>(_: T.Type) {}
        require(WatchServerDescriptor.self); require(WatchSessionSummary.self); require(WatchComposerOptions.self)
        require(WatchRunEvent.self); require(WatchApproval.self); require(WatchClarification.self); require(WatchTaskSummary.self)
        require(WatchSkillDetail.self); require(WatchMemoryDocument.self); require(WatchInsightsAggregate.self); require(WatchWorkspaceEntry.self)
        require(WatchGitAggregate.self); require(WatchBotConversation.self); require(WatchAlertProjection.self)
    }
}

@Suite struct ManifestCoverage_DTOTests {
 @Test func executableTypedManifestCoverage() {
  func requireType<T>(_: T.Type) {}
  requireType(AlertKind.self)
  requireType(AlertSource.self)
  requireType(BotPhoneDestination.self)
  requireType(DirectAccessState.self)
  requireType(GitDiffKind.self)
  requireType(SessionCollection.self)
  requireType(TaskControl.self)
  requireType(WatchAttentionHead<WatchApproval>.self)
  requireType(WatchAuthMode.self)
  requireType(WatchBotActivity.self)
  requireType(WatchBotClarificationForm.self)
  requireType(WatchBotClarificationQuestion.self)
  requireType(WatchBotEvent.self)
  requireType(WatchBotHistoryAvailability.self)
  requireType(WatchBotSummary.self)
  requireType(WatchFilePreview.self)
  requireType(WatchMemorySection.self)
  requireType(WatchMessageRole.self)
  requireType(WatchRunPhase.self)
  requireType(WatchRunState.self)
  requireType(WatchSkillContent.self)
  requireType(WatchSkillSummary.self)
  requireType(WatchTaskRun.self)
  requireType(WatchTaskRunDetail.self)
  requireType(WatchTranscriptBlock.self)
 }
}
