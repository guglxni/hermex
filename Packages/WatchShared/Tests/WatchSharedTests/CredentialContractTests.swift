import Foundation
import Testing
@testable import WatchShared

@Suite struct CredentialContractTests {
    private func scope() throws -> ServerScope { ServerScope(epoch: InstallationEpoch(rawValue: UUID()), server: ServerID(rawValue: UUID()), generation: try Generation(1)) }
    private func fixture(scope: ServerScope? = nil, explicitPort: Bool = true, issuedAt: Date = Date()) throws -> WatchCredentialTransferEnvelope {
        let scope = try scope ?? self.scope()
        let cookieExpiry = issuedAt.addingTimeInterval(600)
        let cookie = try HTTPCookiePropertyRecord(name: "hermes_session", value: "secret-cookie", domain: ".example.com", path: "/", secure: true, expiresAt: cookieExpiry)
        let origin = URL(string: explicitPort ? "https://api.example.com:443" : "https://api.example.com")!
        let credential = try WatchCredentialRecord(scope: scope, origin: origin, cookie: cookie, approvedHeaders: [try HeaderCredentialRecord(name: "X-Hermes-Proxy", value: "secret-header")], expiresAt: cookieExpiry)
        return try WatchCredentialTransferEnvelope(envelopeID: UUID(), scope: scope, issuedAt: issuedAt, expiresAt: issuedAt.addingTimeInterval(300), credential: credential, now: issuedAt)
    }
    private func replacing<T: Encodable>(_ value: T, _ key: String, with replacement: Any) throws -> Data { var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any]); object[key] = replacement; return try JSONSerialization.data(withJSONObject: object) }

    @Test func phoneAndWatchCanonicalFixturesRoundTripBidirectionally() throws {
        for explicit in [false, true] { let envelope = try fixture(explicitPort: explicit); let bytes = try JSONEncoder().encode(envelope); let watch = try JSONDecoder().decode(WatchCredentialTransferEnvelope.self, from: bytes); let phoneBytes = try JSONEncoder().encode(watch); #expect(try JSONDecoder().decode(WatchCredentialTransferEnvelope.self, from: phoneBytes) == envelope) }
    }

    @Test func decodedScopeMismatchAndCredentialLifetimeFailClosed() throws {
        let envelope = try fixture(), other = try scope()
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(envelope)) as? [String: Any])
        object["scope"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(other))
        #expect(throws: (any Error).self) { try JSONDecoder().decode(WatchCredentialTransferEnvelope.self, from: JSONSerialization.data(withJSONObject: object)) }
        object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(envelope)) as? [String: Any])
        object["expiresAt"] = envelope.credential.expiresAt!.addingTimeInterval(1).timeIntervalSinceReferenceDate
        #expect(throws: (any Error).self) { try JSONDecoder().decode(WatchCredentialTransferEnvelope.self, from: JSONSerialization.data(withJSONObject: object)) }
    }

    @Test func originCookieDomainPathAndPortAreCanonicalAndApplicable() throws {
        let scope = try scope(), now = Date(), cookie = try HTTPCookiePropertyRecord(name: "n", value: "v", domain: "example.com", path: "/", secure: true, expiresAt: now.addingTimeInterval(60))
        for invalid in ["http://example.com", "https://user@example.com", "https://example.com/path", "https://example.com?x=1", "https://example.com#x", "https://EXAMPLE.com", "https://example.com:70000"] { #expect(throws: (any Error).self) { try WatchCredentialRecord(scope: scope, origin: URL(string: invalid)!, cookie: cookie, approvedHeaders: [], expiresAt: now.addingTimeInterval(60)) } }
        #expect(throws: (any Error).self) { try WatchCredentialRecord(scope: scope, origin: URL(string: "https://other.example")!, cookie: cookie, approvedHeaders: [], expiresAt: nil) }
        let wrongPath = try HTTPCookiePropertyRecord(name: "n", value: "v", domain: "example.com", path: "/api", secure: true, expiresAt: nil)
        #expect(throws: (any Error).self) { try WatchCredentialRecord(scope: scope, origin: URL(string: "https://example.com")!, cookie: wrongPath, approvedHeaders: [], expiresAt: nil) }
    }

    @Test func completeForbiddenHopByHopAndCasefoldDuplicateHeadersAreRejected() throws {
        let names = ["Host", "Cookie", "Set-Cookie", "Content-Length", "Connection", "Keep-Alive", "Proxy-Authenticate", "Proxy-Authorization", "TE", "Trailer", "Transfer-Encoding", "Upgrade"]
        for name in names { #expect(throws: (any Error).self) { try HeaderCredentialRecord(name: name, value: "x") } }
        let scope = try scope(), cookie = try HTTPCookiePropertyRecord(name: "n", value: "v", domain: "example.com", path: "/", secure: true, expiresAt: nil)
        #expect(throws: (any Error).self) { try WatchCredentialRecord(scope: scope, origin: URL(string: "https://example.com")!, cookie: cookie, approvedHeaders: [try HeaderCredentialRecord(name: "X-Hermes-Proxy", value: "a"), try HeaderCredentialRecord(name: "x-hermes-proxy", value: "b")], expiresAt: nil) }
    }

    @Test func finiteIncreasingDatesFutureSkewAndLifetimeAreEnforcedAtDecode() throws {
        let now = Date(), envelope = try fixture(issuedAt: now)
        #expect(throws: (any Error).self) { try WatchCredentialTransferEnvelope(envelopeID: UUID(), scope: envelope.scope, issuedAt: now.addingTimeInterval(31), expiresAt: now.addingTimeInterval(60), credential: envelope.credential, now: now) }
        #expect(throws: (any Error).self) { try WatchCredentialTransferEnvelope(envelopeID: UUID(), scope: envelope.scope, issuedAt: now, expiresAt: now.addingTimeInterval(301), credential: envelope.credential, now: now) }
        #expect(throws: (any Error).self) { try WatchCredentialTransferEnvelope(envelopeID: UUID(), scope: envelope.scope, issuedAt: .distantFuture, expiresAt: .distantFuture.addingTimeInterval(1), credential: envelope.credential, now: now) }
        #expect(throws: (any Error).self) { try JSONDecoder().decode(WatchCredentialTransferEnvelope.self, from: Data("{\"schemaVersion\":1,\"issuedAt\":1e309}".utf8)) }
    }

    @Test func secretTypesRemainAbsentFromOrdinaryPayloadSources() throws {
        let files = ["Route.swift", "DTOs.swift", "Commands.swift", "Operations.swift", "TransportEnvelope.swift", "OperationResults.swift", "Receipts.swift", "Diagnostics.swift", "Redaction.swift"]
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/WatchShared")
        for file in files { let text = try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8); #expect(!text.contains("WatchCredentialRecord")); #expect(!text.contains("WatchCredentialTransferEnvelope")) }
    }
}
