import Foundation
import Testing
@testable import WatchShared

@Suite struct RedactionTests {
    @Test func exactPlaceholdersAndAliasesAreStableAndBounded() throws {
        let expected: [(SourceTextCategory, String)] = [(.chat, "Private chat content"), (.command, "Private command"), (.question, "Private question"), (.answer, "Private answer"), (.path, "Private path"), (.backendError, "Private server error")]
        for (category, placeholder) in expected { #expect(WatchRedactor.fixedPlaceholder(for: category) == placeholder); #expect(try JSONDecoder().decode(SourceTextCategory.self, from: JSONEncoder().encode(category)) == category) }
        #expect(try WatchRedactor.displayName(aliasIndex: 0).rawValue == "Server1")
        #expect(try WatchRedactor.displayName(aliasIndex: 999).rawValue == "Server1000")
        #expect(throws: (any Error).self) { try WatchRedactor.displayName(aliasIndex: -1) }
    }

    @Test func utf8AndControlBoundariesFailClosed() throws {
        let exact = Data(String(repeating: "é", count: 8192).utf8)
        try WatchRedactor.validateNonSecretProjection(exact, context: .log)
        #expect(throws: (any Error).self) { try WatchRedactor.validateNonSecretProjection(Data(String(repeating: "é", count: 8193).utf8), context: .log) }
        for byte in [UInt8(0), 1, 8, 9, 10, 11, 12, 13, 31, 127] { #expect(throws: (any Error).self) { try WatchRedactor.validateNonSecretProjection(Data([65, byte, 66]), context: .log) } }
        #expect(throws: (any Error).self) { try WatchRedactor.validateNonSecretProjection(Data([0xff]), context: .log) }
    }

    @Test func realRouteWidgetDiagnosticReceiptAndLogSafeOutputsContainNoCanary() throws {
        let scope = ServerScope(epoch: InstallationEpoch(rawValue: UUID()), server: ServerID(rawValue: UUID()), generation: try Generation(1))
        let now = Date(timeIntervalSinceReferenceDate: 100)
        let route = try WatchHandoffRoute(routeID: UUID(), scope: scope, target: .diagnostics(scope), createdAt: now, expiresAt: now.addingTimeInterval(60))
        let widget = try RedactedWidgetSnapshot(schema: 1, scope: scope, displayName: RedactedDisplayName("Server1"), activity: .unknown, attentionCount: 0, observedAt: now, route: .sessions(scope))
        let diagnostic = try WatchDiagnosticsProjection(scope: scope, source: .snapshot, observedAt: now, expiresAt: now.addingTimeInterval(60), codes: [.timeout])
        let context = try CommandContext(stableCommandID: CommandID(rawValue: UUID()), scope: scope, expectedRevision: Revision(1), createdAt: now, expiresAt: now.addingTimeInterval(60))
        let receipt = try MutationReceipt(context: context, operationKind: .stop, phase: .rejected, updatedAt: now, nonSecretResultID: "attentionExactIDUnavailable")
        let outputs: [(RedactionContext, Data)] = [(.route, try JSONEncoder().encode(route)), (.widget, try JSONEncoder().encode(widget)), (.diagnostics, try JSONEncoder().encode(diagnostic)), (.receipt, try JSONEncoder().encode(receipt)), (.log, Data("attentionExactIDUnavailable".utf8))]
        for (context, output) in outputs { try WatchRedactor.validateNonSecretProjection(output, context: context); #expect(!String(decoding: output, as: UTF8.self).contains("U01C_SECRET_CANARY")) }
        for context in [RedactionContext.route, .widget, .diagnostics, .receipt, .log] { #expect(throws: (any Error).self) { try WatchRedactor.validateNonSecretProjection(Data("U01C_SECRET_CANARY authorization=https://host/private".utf8), context: context) } }
    }
}
