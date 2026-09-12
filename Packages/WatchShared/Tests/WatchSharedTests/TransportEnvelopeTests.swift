import Foundation
import Testing
import WatchShared

@Suite struct TransportEnvelopeTests {
    private struct Fixtures {
        let scope: ServerScope
        let otherScope: ServerScope
        let session: SessionKey
        let run: RunKey
        let context: CommandContext
        let created: Date
        let expires: Date
    }

    private func fixtures() throws -> Fixtures {
        let epoch = InstallationEpoch(rawValue: UUID(uuidString: "30000000-0000-0000-0000-000000000001")!)
        let scope = ServerScope(epoch: epoch, server: ServerID(rawValue: UUID(uuidString: "30000000-0000-0000-0000-000000000002")!), generation: try Generation(3))
        let otherScope = ServerScope(epoch: epoch, server: ServerID(rawValue: UUID(uuidString: "30000000-0000-0000-0000-000000000003")!), generation: try Generation(3))
        let session = try SessionKey(scope: scope, sessionID: "session")
        let created = Date().addingTimeInterval(60)
        let expires = created.addingTimeInterval(120)
        return Fixtures(
            scope: scope,
            otherScope: otherScope,
            session: session,
            run: try RunKey(session: session, streamID: "run"),
            context: try CommandContext(stableCommandID: CommandID(rawValue: UUID(uuidString: "30000000-0000-0000-0000-000000000004")!), scope: scope, expectedRevision: Revision(12), createdAt: created, expiresAt: expires),
            created: created,
            expires: expires
        )
    }

    private func mutate(_ value: some Encodable, key: String, to replacement: Any) throws -> Data {
        let encoded = try JSONEncoder().encode(value)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object[key] = replacement
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func object(_ value: some Encodable) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    }

    private func data(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    @Test func semanticCoverage_WatchRequestEnvelope() throws {
        let f = try fixtures()
        let read = try WatchRequestEnvelope.read(
            requestID: UUID(uuidString: "30000000-0000-0000-0000-000000000005")!,
            scope: f.scope,
            operation: .diagnostics(scope: f.scope),
            createdAt: f.created,
            expiresAt: f.expires
        )
        let stream = try WatchRequestEnvelope.stream(
            requestID: UUID(uuidString: "30000000-0000-0000-0000-000000000006")!,
            scope: f.scope,
            operation: .run(f.run, afterEventID: "event"),
            createdAt: f.created,
            expiresAt: f.expires
        )
        #expect(read.operationKind == .diagnostics)
        #expect(stream.operationKind == .runStream)
        for value in [read, stream] {
            let encoded = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(WatchRequestEnvelope.self, from: encoded)
            #expect(decoded == value)
        }

        let invalid: [WatchRequestEnvelope] = [
            .read(schemaVersion: 2, requestID: UUID(), scope: f.scope, operationKind: .diagnostics, operation: .diagnostics(scope: f.scope), createdAt: f.created, expiresAt: f.expires),
            .read(schemaVersion: 1, requestID: UUID(), scope: f.otherScope, operationKind: .diagnostics, operation: .diagnostics(scope: f.scope), createdAt: f.created, expiresAt: f.expires),
            .read(schemaVersion: 1, requestID: UUID(), scope: f.scope, operationKind: .sessions, operation: .diagnostics(scope: f.scope), createdAt: f.created, expiresAt: f.expires),
            .read(schemaVersion: 1, requestID: UUID(), scope: f.scope, operationKind: .diagnostics, operation: .diagnostics(scope: f.scope), createdAt: f.created, expiresAt: f.created),
            .stream(schemaVersion: 1, requestID: UUID(), scope: f.scope, operationKind: .botStream, operation: .run(f.run, afterEventID: nil), createdAt: f.created, expiresAt: f.expires),
        ]
        for value in invalid {
            #expect(throws: (any Error).self) {
                try JSONDecoder().decode(WatchRequestEnvelope.self, from: JSONEncoder().encode(value))
            }
        }

        let expired = WatchRequestEnvelope.read(schemaVersion: 1, requestID: UUID(), scope: f.scope, operationKind: .diagnostics, operation: .diagnostics(scope: f.scope), createdAt: Date().addingTimeInterval(-120), expiresAt: Date().addingTimeInterval(-60))
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(WatchRequestEnvelope.self, from: JSONEncoder().encode(expired))
        }
    }

    @Test func semanticCoverage_WatchMutationRequest() throws {
        let f = try fixtures()
        let value = try WatchMutationRequest(
            requestID: UUID(uuidString: "30000000-0000-0000-0000-000000000007")!,
            context: f.context,
            operation: .send(session: f.session, text: "hello"),
            createdAt: f.created,
            expiresAt: f.expires
        )
        #expect(value.schemaVersion == 1)
        #expect(value.context == f.context)
        #expect(value.operationKind == .send)
        #expect(value.operation.scope == f.scope)
        #expect(value.createdAt == f.context.createdAt)
        #expect(value.expiresAt == f.context.expiresAt)

        let encoded = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(WatchMutationRequest.self, from: encoded)
        #expect(decoded == value)

        #expect(throws: EnvelopeValidationError.contextMismatch) {
            try WatchMutationRequest(requestID: UUID(), context: f.context, operation: .send(session: f.session, text: "hello"), createdAt: f.created, expiresAt: f.expires.addingTimeInterval(1))
        }
        let otherSession = try SessionKey(scope: f.otherScope, sessionID: "other")
        #expect(throws: EnvelopeValidationError.scopeMismatch) {
            try WatchMutationRequest(requestID: UUID(), context: f.context, operation: .send(session: otherSession, text: "hello"), createdAt: f.created, expiresAt: f.expires)
        }
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(WatchMutationRequest.self, from: mutate(value, key: "schemaVersion", to: 2))
        }
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(WatchMutationRequest.self, from: mutate(value, key: "operationKind", to: "stop"))
        }

        let oldCreated = Date().addingTimeInterval(-120)
        let oldContext = try CommandContext(stableCommandID: CommandID(rawValue: UUID()), scope: f.scope, expectedRevision: Revision(1), createdAt: oldCreated, expiresAt: oldCreated.addingTimeInterval(30))
        let expired = try WatchMutationRequest(requestID: UUID(), context: oldContext, operation: .send(session: f.session, text: "hello"), createdAt: oldContext.createdAt, expiresAt: oldContext.expiresAt)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(WatchMutationRequest.self, from: JSONEncoder().encode(expired))
        }

        let oversized = try WatchMutationRequest(requestID: UUID(), context: f.context, operation: .send(session: f.session, text: String(repeating: "x", count: 16_000)), createdAt: f.created, expiresAt: f.expires)
        #expect(throws: (any Error).self) {
            try WatchMutationRequest.decodeLive(JSONEncoder().encode(oversized))
        }
    }

    @Test func mutationRequestInitializerRejectsInvalidDirectOperation() throws {
        let f = try fixtures()
        let invalidOperation = WatchMutationOperation.send(session: f.session, text: " ")

        #expect(throws: (any Error).self) {
            try WatchMutationRequest(
                requestID: UUID(),
                context: f.context,
                operation: invalidOperation,
                createdAt: f.created,
                expiresAt: f.expires
            )
        }
    }

    @Test func responseInitializerRejectsInvalidNestedResultScope() throws {
        let f = try fixtures()
        let freshness = try Freshness(observedAt: f.created, expiresAt: f.expires, source: .phoneProjection)
        let foreignDiagnostics = try WatchDiagnosticsProjection(
            scope: f.otherScope,
            source: .phoneBroker,
            observedAt: f.created,
            expiresAt: f.expires,
            codes: [.timeout]
        )
        let invalidResult = WatchOperationResult.diagnostics(
            try ScopedSnapshot(
                schema: 1,
                scope: f.scope,
                revision: Revision(13),
                freshness: freshness,
                value: foreignDiagnostics
            )
        )

        #expect(throws: EnvelopeValidationError.scopeMismatch) {
            try WatchResponseEnvelope(
                requestID: UUID(),
                scope: f.scope,
                requestOperationKind: .diagnostics,
                requestCreatedAt: f.created,
                requestExpiresAt: f.expires,
                commandContext: nil,
                result: invalidResult
            )
        }
    }

    @Test func semanticCoverage_WatchResponseEnvelope() throws {
        let f = try fixtures()
        let freshness = try Freshness(observedAt: f.created, expiresAt: f.expires, source: .phoneProjection)
        let diagnostics = try WatchDiagnosticsProjection(scope: f.scope, source: .phoneBroker, observedAt: f.created, expiresAt: f.expires, codes: [.timeout])
        let snapshot = try ScopedSnapshot(schema: 1, scope: f.scope, revision: Revision(13), freshness: freshness, value: diagnostics)
        let requestID = UUID(uuidString: "30000000-0000-0000-0000-000000000008")!
        let request = try WatchRequestEnvelope.read(requestID: requestID, scope: f.scope, operation: .diagnostics(scope: f.scope), createdAt: f.created, expiresAt: f.expires)
        let response = try WatchResponseEnvelope(requestID: requestID, scope: f.scope, requestOperationKind: .diagnostics, requestCreatedAt: f.created, requestExpiresAt: f.expires, commandContext: nil, result: .diagnostics(snapshot))
        #expect(response.schemaVersion == 1)
        #expect(response.result.kind == .diagnostics)
        #expect(response.result.scope == f.scope)

        let encoded = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(WatchResponseEnvelope.self, from: encoded)
        #expect(decoded == response)
        try response.validate(against: request, receivedAt: f.created)

        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(WatchResponseEnvelope.self, from: mutate(response, key: "schemaVersion", to: 2))
        }
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(WatchResponseEnvelope.self, from: mutate(response, key: "requestOperationKind", to: "sessions"))
        }
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(WatchResponseEnvelope.self, from: mutate(response, key: "scope", to: JSONSerialization.jsonObject(with: JSONEncoder().encode(f.otherScope))))
        }
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(WatchResponseEnvelope.self, from: mutate(response, key: "commandContext", to: JSONSerialization.jsonObject(with: JSONEncoder().encode(f.context))))
        }

        let wrongRequest = try WatchRequestEnvelope.read(requestID: UUID(), scope: f.scope, operation: .diagnostics(scope: f.scope), createdAt: f.created, expiresAt: f.expires)
        #expect(throws: (any Error).self) { try response.validate(against: wrongRequest, receivedAt: f.created) }
        #expect(throws: (any Error).self) { try response.validate(against: request, receivedAt: f.expires.addingTimeInterval(1)) }

        let mutationRequest = try WatchMutationRequest(requestID: requestID, context: f.context, operation: .send(session: f.session, text: "hello"), createdAt: f.created, expiresAt: f.expires)
        let mutationReceipt = try MutationReceipt(context: f.context, operationKind: .send, phase: .acknowledged, updatedAt: f.created, nonSecretResultID: "run")
        let mutationResponse = try WatchResponseEnvelope(requestID: requestID, scope: f.scope, requestOperationKind: .send, requestCreatedAt: f.created, requestExpiresAt: f.expires, commandContext: f.context, result: .startedRun(CommandReceipt(receipt: mutationReceipt, value: f.run)))
        let mutationEncoded = try JSONEncoder().encode(mutationResponse)
        #expect(try JSONDecoder().decode(WatchResponseEnvelope.self, from: mutationEncoded) == mutationResponse)
        try mutationResponse.validate(against: mutationRequest, receivedAt: f.created)

        var expiredObject = try object(response)
        expiredObject["requestCreatedAt"] = Date().addingTimeInterval(-120).timeIntervalSinceReferenceDate
        expiredObject["requestExpiresAt"] = Date().addingTimeInterval(-60).timeIntervalSinceReferenceDate
        #expect(throws: EnvelopeValidationError.expired) {
            try JSONDecoder().decode(WatchResponseEnvelope.self, from: data(expiredObject))
        }

        let wrongContext = try CommandContext(
            stableCommandID: CommandID(rawValue: UUID()),
            scope: f.scope,
            expectedRevision: f.context.expectedRevision,
            createdAt: f.created,
            expiresAt: f.expires
        )
        let tamperedMutationResponses: [Data] = try [
            mutate(mutationResponse, key: "requestID", to: UUID().uuidString),
            mutate(mutationResponse, key: "scope", to: JSONSerialization.jsonObject(with: JSONEncoder().encode(f.otherScope))),
            mutate(mutationResponse, key: "requestOperationKind", to: "stop"),
            mutate(mutationResponse, key: "requestCreatedAt", to: f.created.addingTimeInterval(1).timeIntervalSinceReferenceDate),
            mutate(mutationResponse, key: "requestExpiresAt", to: f.expires.addingTimeInterval(1).timeIntervalSinceReferenceDate),
            mutate(mutationResponse, key: "commandContext", to: JSONSerialization.jsonObject(with: JSONEncoder().encode(wrongContext))),
        ]
        for tampered in tamperedMutationResponses {
            #expect(throws: (any Error).self) {
                let decodedTampered = try JSONDecoder().decode(WatchResponseEnvelope.self, from: tampered)
                try decodedTampered.validate(against: mutationRequest, receivedAt: f.created)
            }
        }

        var receiptObject = try object(mutationResponse)
        var resultObject = try #require(receiptObject["result"] as? [String: Any])
        var startedRun = try #require(resultObject["startedRun"] as? [String: Any])
        var wrappedReceipt = try #require(startedRun["_0"] as? [String: Any])
        var receipt = try #require(wrappedReceipt["receipt"] as? [String: Any])
        receipt["operationKind"] = "stop"
        wrappedReceipt["receipt"] = receipt
        startedRun["_0"] = wrappedReceipt
        resultObject["startedRun"] = startedRun
        receiptObject["result"] = resultObject
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(WatchResponseEnvelope.self, from: data(receiptObject))
        }

        var resultFamilyObject = try object(mutationResponse)
        resultFamilyObject["result"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(WatchOperationResult.mutation(CommandReceipt(receipt: mutationReceipt, value: EmptyValue()))))
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(WatchResponseEnvelope.self, from: data(resultFamilyObject))
        }

        var oversized = encoded
        oversized.append(Data(repeating: 0x20, count: 262_145))
        #expect(throws: (any Error).self) { try WatchResponseEnvelope.decodeLive(oversized) }
    }
}
