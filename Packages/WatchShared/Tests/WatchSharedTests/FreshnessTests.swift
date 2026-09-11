import Foundation
import Testing
@testable import WatchShared

@Suite struct FreshnessTests {
    @Test func freshnessRetainsFiniteTimesAndSource() throws {
        let observed = Date(timeIntervalSinceReferenceDate: 100)
        let expires = Date(timeIntervalSinceReferenceDate: 200)
        let value = try Freshness(observedAt: observed, expiresAt: expires, source: .directServer)
        #expect(value.observedAt == observed)
        #expect(value.expiresAt == expires)
        #expect(value.source == .directServer)
    }

    @Test func freshnessRejectsNonfiniteObservation() {
        #expect(throws: FreshnessValidationError.nonfiniteTimestamp) {
            try Freshness(
                observedAt: Date(timeIntervalSinceReferenceDate: .infinity),
                expiresAt: nil,
                source: .cache
            )
        }
    }

    @Test func freshnessRejectsNonfiniteExpiry() {
        #expect(throws: FreshnessValidationError.nonfiniteTimestamp) {
            try Freshness(
                observedAt: Date(timeIntervalSinceReferenceDate: 0),
                expiresAt: Date(timeIntervalSinceReferenceDate: .nan),
                source: .phoneProjection
            )
        }
    }

    @Test func freshnessRejectsExpiryBeforeObservation() {
        #expect(throws: FreshnessValidationError.expiryBeforeObservation) {
            try Freshness(
                observedAt: Date(timeIntervalSinceReferenceDate: 10),
                expiresAt: Date(timeIntervalSinceReferenceDate: 9),
                source: .directServer
            )
        }
    }

    @Test func isFreshHonorsObservationAndExclusiveExpiry() throws {
        let value = try Freshness(
            observedAt: Date(timeIntervalSinceReferenceDate: 10),
            expiresAt: Date(timeIntervalSinceReferenceDate: 20),
            source: .directServer
        )
        #expect(!value.isFresh(at: Date(timeIntervalSinceReferenceDate: 9)))
        #expect(value.isFresh(at: Date(timeIntervalSinceReferenceDate: 10)))
        #expect(value.isFresh(at: Date(timeIntervalSinceReferenceDate: 19)))
        #expect(!value.isFresh(at: Date(timeIntervalSinceReferenceDate: 20)))
    }

    @Test func freshnessWithoutExpiryNeverAuthorizesMutation() throws {
        let noExpiry = try Freshness(observedAt: Date(timeIntervalSinceReferenceDate: 10), expiresAt: nil, source: .directServer)
        let expiring = try Freshness(observedAt: Date(timeIntervalSinceReferenceDate: 10), expiresAt: Date(timeIntervalSinceReferenceDate: 20), source: .directServer)
        #expect(!noExpiry.isFresh(at: Date(timeIntervalSinceReferenceDate: 10)))
        #expect(!noExpiry.authorizesMutation(at: Date(timeIntervalSinceReferenceDate: 10)))
        #expect(expiring.authorizesMutation(at: Date(timeIntervalSinceReferenceDate: 10)))
        #expect(!expiring.authorizesMutation(at: Date(timeIntervalSinceReferenceDate: 20)))
    }

    @Test func freshnessDecodingRevalidatesTimes() throws {
        let invalid = Data("{\"observedAt\":10,\"expiresAt\":9,\"source\":\"cache\"}".utf8)
        #expect(throws: FreshnessValidationError.expiryBeforeObservation) {
            try JSONDecoder().decode(Freshness.self, from: invalid)
        }
    }

    @Test func scopedSnapshotCarriesSchemaOneAndValue() throws {
        let scope = ServerScope(
            epoch: InstallationEpoch(rawValue: UUID()),
            server: ServerID(rawValue: UUID()),
            generation: try Generation(1)
        )
        let freshness = try Freshness(
            observedAt: Date(timeIntervalSinceReferenceDate: 1),
            expiresAt: nil,
            source: .cache
        )
        let snapshot = try ScopedSnapshot(schema: 1, scope: scope, revision: Revision(2), freshness: freshness, value: "payload")
        #expect(snapshot.schema == 1)
        #expect(snapshot.value == "payload")
        #expect(try JSONDecoder().decode(ScopedSnapshot<String>.self, from: JSONEncoder().encode(snapshot)).value == "payload")
    }

    @Test func scopedSnapshotRequiresSchemaOne() throws {
        let scope = ServerScope(
            epoch: InstallationEpoch(rawValue: UUID()),
            server: ServerID(rawValue: UUID()),
            generation: try Generation(1)
        )
        let freshness = try Freshness(observedAt: Date(timeIntervalSinceReferenceDate: 1), expiresAt: nil, source: .cache)
        #expect(throws: FreshnessValidationError.unsupportedSchema(2)) {
            try ScopedSnapshot(schema: 2, scope: scope, revision: Revision(0), freshness: freshness, value: "payload")
        }
    }

    @Test func scopedSnapshotDecodingRevalidatesSchema() throws {
        let scope = ServerScope(
            epoch: InstallationEpoch(rawValue: UUID()),
            server: ServerID(rawValue: UUID()),
            generation: try Generation(1)
        )
        let freshness = try Freshness(observedAt: Date(timeIntervalSinceReferenceDate: 1), expiresAt: nil, source: .cache)
        let valid = try ScopedSnapshot(schema: 1, scope: scope, revision: Revision(0), freshness: freshness, value: "payload")
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(valid)) as? [String: Any])
        object["schema"] = 2
        #expect(throws: FreshnessValidationError.unsupportedSchema(2)) {
            try JSONDecoder().decode(ScopedSnapshot<String>.self, from: JSONSerialization.data(withJSONObject: object))
        }
    }

    @Test func registrySnapshotEncodesSchemaOneAndRejectsUnknownSchema() throws {
        let epoch = InstallationEpoch(rawValue: UUID())
        let snapshot = try RegistrySnapshot(
            epoch: epoch,
            revision: Revision(1),
            generatedAt: Date(timeIntervalSinceReferenceDate: 20),
            entries: []
        )

        let data = try JSONEncoder().encode(snapshot)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(snapshot.schemaVersion == 1)
        #expect(object["schemaVersion"] as? Int == 1)

        var invalid = object
        invalid["schemaVersion"] = 2
        #expect(throws: RegistryValidationError.unsupportedSchema(2)) {
            try JSONDecoder().decode(RegistrySnapshot.self, from: JSONSerialization.data(withJSONObject: invalid))
        }
    }

    @Test func registryEntryCarriesScopeAndValidatedDisplayName() throws {
        let scope = ServerScope(
            epoch: InstallationEpoch(rawValue: UUID()),
            server: ServerID(rawValue: UUID()),
            generation: try Generation(1)
        )
        let name = try RedactedDisplayName("Server")
        let entry = RegistryEntry(scope: scope, displayName: name)
        #expect(entry.scope == scope)
        #expect(entry.displayName == name)
    }

    @Test func registrySnapshotCarriesRegistryState() throws {
        let epoch = InstallationEpoch(rawValue: UUID())
        let entry = RegistryEntry(
            scope: ServerScope(epoch: epoch, server: ServerID(rawValue: UUID()), generation: try Generation(1)),
            displayName: try RedactedDisplayName("Server")
        )
        let generatedAt = Date(timeIntervalSinceReferenceDate: 20)
        let snapshot = try RegistrySnapshot(epoch: epoch, revision: Revision(3), generatedAt: generatedAt, entries: [entry])
        #expect(snapshot.epoch == epoch)
        #expect(snapshot.revision == Revision(3))
        #expect(snapshot.generatedAt == generatedAt)
        #expect(snapshot.entries == [entry])
    }

    @Test func registrySnapshotRejectsNonfiniteGeneratedAt() {
        #expect(throws: RegistryValidationError.nonfiniteGeneratedAt) {
            try RegistrySnapshot(
                epoch: InstallationEpoch(rawValue: UUID()),
                revision: Revision(0),
                generatedAt: Date(timeIntervalSinceReferenceDate: .infinity),
                entries: []
            )
        }
    }

    @Test func registrySnapshotRejectsMoreThan32Entries() throws {
        let epoch = InstallationEpoch(rawValue: UUID())
        let entries = try (0..<33).map { index in
            RegistryEntry(
                scope: ServerScope(epoch: epoch, server: ServerID(rawValue: UUID()), generation: try Generation(1)),
                displayName: try RedactedDisplayName("Server \(index)")
            )
        }
        #expect(throws: RegistryValidationError.tooManyEntries) {
            try RegistrySnapshot(epoch: epoch, revision: Revision(0), generatedAt: Date(), entries: entries)
        }
    }

    @Test func registrySnapshotRejectsDuplicateServers() throws {
        let epoch = InstallationEpoch(rawValue: UUID())
        let server = ServerID(rawValue: UUID())
        let entries = try [1, 2].map { generation in
            RegistryEntry(
                scope: ServerScope(epoch: epoch, server: server, generation: try Generation(UInt64(generation))),
                displayName: try RedactedDisplayName("Server \(generation)")
            )
        }
        #expect(throws: RegistryValidationError.duplicateServer(server)) {
            try RegistrySnapshot(epoch: epoch, revision: Revision(0), generatedAt: Date(), entries: entries)
        }
    }

    @Test func registrySnapshotRejectsEntryFromAnotherEpoch() throws {
        let epoch = InstallationEpoch(rawValue: UUID())
        let other = InstallationEpoch(rawValue: UUID())
        let entry = RegistryEntry(
            scope: ServerScope(epoch: other, server: ServerID(rawValue: UUID()), generation: try Generation(1)),
            displayName: try RedactedDisplayName("Server")
        )
        #expect(throws: RegistryValidationError.epochMismatch) {
            try RegistrySnapshot(epoch: epoch, revision: Revision(0), generatedAt: Date(), entries: [entry])
        }
    }

    @Test func registrySnapshotDecodingRevalidatesEntries() throws {
        let epoch = InstallationEpoch(rawValue: UUID())
        let entry = RegistryEntry(
            scope: ServerScope(epoch: epoch, server: ServerID(rawValue: UUID()), generation: try Generation(1)),
            displayName: try RedactedDisplayName("Server")
        )
        let valid = try RegistrySnapshot(epoch: epoch, revision: Revision(1), generatedAt: Date(), entries: [entry])
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(valid)) as? [String: Any])
        object["entries"] = Array(repeating: try #require(object["entries"] as? [Any]).first!, count: 33)
        #expect(throws: RegistryValidationError.tooManyEntries) {
            try JSONDecoder().decode(RegistrySnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        }
    }
}
