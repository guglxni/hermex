import Foundation
import Testing
@testable import WatchShared

@Suite struct IdentityTests {
    @Test func installationEpochRoundTripsWithNestedCanonicalUUID() throws {
        let uuid = UUID(uuidString: "123E4567-E89B-12D3-A456-426614174000")!
        let value = InstallationEpoch(rawValue: uuid)

        let data = try JSONEncoder().encode(value)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: String])
        #expect(object == ["rawValue": uuid.uuidString])
        #expect(try JSONDecoder().decode(InstallationEpoch.self, from: data) == value)
    }

    @Test func serverIDRoundTripsWithNestedCanonicalUUIDIncludingNilUUID() throws {
        let value = ServerID(rawValue: UUID())
        let data = try JSONEncoder().encode(value)
        #expect(try JSONDecoder().decode(ServerID.self, from: data) == value)

        let nilValue = ServerID(rawValue: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)))
        #expect(try JSONDecoder().decode(ServerID.self, from: JSONEncoder().encode(nilValue)) == nilValue)
    }

    @Test func generationRejectsZeroAtInitialization() {
        #expect(throws: IdentityValidationError.generationMustBePositive) {
            try Generation(0)
        }
    }

    @Test func generationUsesSingleIntegerAndValidatesDecoding() throws {
        let value = try Generation(7)
        let data = try JSONEncoder().encode(value)
        #expect(String(decoding: data, as: UTF8.self) == "7")
        #expect(try JSONDecoder().decode(Generation.self, from: data) == value)
        #expect(throws: IdentityValidationError.generationMustBePositive) {
            try JSONDecoder().decode(Generation.self, from: Data("0".utf8))
        }
    }

    @Test func serverScopeCarriesEpochServerAndGeneration() throws {
        let epoch = InstallationEpoch(rawValue: UUID())
        let server = ServerID(rawValue: UUID())
        let generation = try Generation(3)
        let scope = ServerScope(epoch: epoch, server: server, generation: generation)
        #expect(scope.epoch == epoch)
        #expect(scope.server == server)
        #expect(scope.generation == generation)
        #expect(try JSONDecoder().decode(ServerScope.self, from: JSONEncoder().encode(scope)) == scope)
    }

    @Test func revisionUsesSingleNonnegativeInteger() throws {
        let zero = Revision(0)
        #expect(String(decoding: try JSONEncoder().encode(zero), as: UTF8.self) == "0")
        #expect(try JSONDecoder().decode(Revision.self, from: Data("42".utf8)) == Revision(42))
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Revision.self, from: Data("-1".utf8))
        }
    }

    @Test func sessionKeyPreservesAcceptedIdentifierBytes() throws {
        let scope = ServerScope(
            epoch: InstallationEpoch(rawValue: UUID()),
            server: ServerID(rawValue: UUID()),
            generation: try Generation(1)
        )
        let original = "  Session/Ω  "
        let key = try SessionKey(scope: scope, sessionID: original)
        #expect(key.scope == scope)
        #expect(key.sessionID == original)
    }

    @Test func sessionKeyRejectsBlankOnlyIdentifier() throws {
        let scope = ServerScope(
            epoch: InstallationEpoch(rawValue: UUID()),
            server: ServerID(rawValue: UUID()),
            generation: try Generation(1)
        )
        #expect(throws: IdentityValidationError.blankIdentifier) {
            try SessionKey(scope: scope, sessionID: " \t\n ")
        }
    }

    @Test func sessionKeyEnforcesUTF8ByteLimit() throws {
        let scope = ServerScope(
            epoch: InstallationEpoch(rawValue: UUID()),
            server: ServerID(rawValue: UUID()),
            generation: try Generation(1)
        )
        #expect(try SessionKey(scope: scope, sessionID: String(repeating: "a", count: 256)).sessionID.utf8.count == 256)
        #expect(throws: IdentityValidationError.identifierTooLong(maxUTF8Bytes: 256)) {
            try SessionKey(scope: scope, sessionID: String(repeating: "é", count: 129))
        }
    }

    @Test func sessionKeyDecodingRevalidatesIdentifier() throws {
        let scope = ServerScope(
            epoch: InstallationEpoch(rawValue: UUID()),
            server: ServerID(rawValue: UUID()),
            generation: try Generation(1)
        )
        let valid = try SessionKey(scope: scope, sessionID: "valid")
        #expect(try JSONDecoder().decode(SessionKey.self, from: JSONEncoder().encode(valid)) == valid)

        let invalid = Data("{\"scope\":\(String(decoding: try JSONEncoder().encode(scope), as: UTF8.self)),\"sessionID\":\"   \"}".utf8)
        #expect(throws: IdentityValidationError.blankIdentifier) {
            try JSONDecoder().decode(SessionKey.self, from: invalid)
        }
    }

    @Test func botKeyPreservesProfileBytesAndTypedConnection() throws {
        let scope = ServerScope(
            epoch: InstallationEpoch(rawValue: UUID()),
            server: ServerID(rawValue: UUID()),
            generation: try Generation(1)
        )
        let connectionID = UUID()
        let original = "  Profile/Ω  "
        let key = try BotKey(scope: scope, connectionID: connectionID, profile: original)
        #expect(key.scope == scope)
        #expect(key.connectionID == connectionID)
        #expect(key.profile == original)
    }

    @Test func botKeyRejectsBlankAndOver128UTF8Profiles() throws {
        let scope = ServerScope(
            epoch: InstallationEpoch(rawValue: UUID()),
            server: ServerID(rawValue: UUID()),
            generation: try Generation(1)
        )
        #expect(throws: IdentityValidationError.blankIdentifier) {
            try BotKey(scope: scope, connectionID: UUID(), profile: " \n")
        }
        #expect(throws: IdentityValidationError.identifierTooLong(maxUTF8Bytes: 128)) {
            try BotKey(scope: scope, connectionID: UUID(), profile: String(repeating: "é", count: 65))
        }
    }

    @Test func botKeyDecodingRevalidatesProfile() throws {
        let scope = ServerScope(
            epoch: InstallationEpoch(rawValue: UUID()),
            server: ServerID(rawValue: UUID()),
            generation: try Generation(1)
        )
        let valid = try BotKey(scope: scope, connectionID: UUID(), profile: "profile")
        #expect(try JSONDecoder().decode(BotKey.self, from: JSONEncoder().encode(valid)) == valid)

        let scopeJSON = String(decoding: try JSONEncoder().encode(scope), as: UTF8.self)
        let invalid = Data("{\"scope\":\(scopeJSON),\"connectionID\":\"\(UUID().uuidString)\",\"profile\":\"\"}".utf8)
        #expect(throws: IdentityValidationError.blankIdentifier) {
            try JSONDecoder().decode(BotKey.self, from: invalid)
        }
    }
}
