import Foundation
import Testing
@testable import WatchShared

@Suite struct RouteTests {
    private func scope() throws -> ServerScope {
        ServerScope(
            epoch: InstallationEpoch(rawValue: UUID()),
            server: ServerID(rawValue: UUID()),
            generation: try Generation(1)
        )
    }

    @Test func routeCasesRoundTripThroughSchemaOneEnvelope() throws {
        let scope = try scope()
        let session = try SessionKey(scope: scope, sessionID: "session/Ω")
        let bot = try BotKey(scope: scope, connectionID: UUID(), profile: "profile Ω")
        let routes: [RedactedRoute] = [
            .servers(scope.epoch),
            .sessions(scope),
            .session(session),
            .bot(bot),
        ]
        for route in routes {
            let data = try route.canonicalJSONData()
            #expect(try RedactedRoute.decode(data) == route)
            let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(object["schema"] as? Int == 1)
        }
    }

    @Test func routeRejectsOversizeBeforeDecode() {
        let oversized = Data(repeating: 0x20, count: 1025)
        #expect(throws: RouteValidationError.tooLarge) {
            try RedactedRoute.decode(oversized)
        }
    }

    @Test func directDecoderCannotBypassSchema() throws {
        let route = RedactedRoute.servers(InstallationEpoch(rawValue: UUID()))
        var object = try #require(JSONSerialization.jsonObject(with: route.canonicalJSONData()) as? [String: Any])
        object["schema"] = 2
        let data = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: RouteValidationError.unsupportedSchema(2)) { try RedactedRoute.decode(data) }
        #expect(throws: RouteValidationError.unsupportedSchema(2)) { try JSONDecoder().decode(RedactedRoute.self, from: data) }
    }

    @Test func cacheKeysAreBase64URLDerivedFromTypedValues() throws {
        let scope = try scope()
        let first = try SessionKey(scope: scope, sessionID: "session/Ω one")
        let second = try SessionKey(scope: scope, sessionID: "session/Ω two")
        let firstKey = try CacheKey.session(first)
        let secondKey = try CacheKey.session(second)
        #expect(firstKey != secondKey)
        #expect(firstKey.rawValue.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") })
        #expect(!firstKey.rawValue.contains("session"))
        #expect(!firstKey.rawValue.contains("/"))
        #expect(!firstKey.rawValue.contains("="))
    }

    @Test func cacheKeysCoverEveryTypedRouteIdentity() throws {
        let scope = try scope()
        let session = try SessionKey(scope: scope, sessionID: "s")
        let bot = try BotKey(scope: scope, connectionID: UUID(), profile: "p")
        let keys = [
            try CacheKey.scope(scope),
            try CacheKey.session(session),
            try CacheKey.bot(bot),
        ]
        #expect(Set(keys).count == 3)
        #expect(keys.allSatisfy { !$0.rawValue.isEmpty })
    }
}
