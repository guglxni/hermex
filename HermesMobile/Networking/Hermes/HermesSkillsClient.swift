import Foundation

/// The Skills screens' client on a Hermes host (#1069): one Profile's skills under `/api/skills`,
/// over the sign-in, headers and cookie jar the server's Bot screens share. Every read and the
/// toggle name that Profile. The host sends no tags, related skills or linked files
/// (`skillsFeatures`), and the host path its SKILL.md read returns is never decoded. A refusal
/// the host explains, such as a skill that is gone, reads as its `detail`.
@MainActor final class HermesSkillsClient: SkillsDataClient {
    nonisolated var skillsFeatures: SkillsFeatures { .hermes }
    let profile: String
    private let http: HermesConnection

    /// `profile`'s skills on `server`'s saved connection, on the sign-in its Bot screens share.
    convenience init(saved connection: BotConnection, server: URL, profile: String) {
        self.init(http: HermesConnections.shared.connection(for: connection, server: server), profile: profile)
    }

    init(http: HermesConnection, profile: String) {
        self.http = http
        self.profile = profile
    }

    func skills() async throws -> SkillsResponse {
        SkillsResponse(skills: try Self.skills(try await send(.skills(profile: profile))))
    }

    /// SKILL.md alone: the screens ask for no linked file here (`skillsFeatures`).
    func skillContent(name: String, file: String?) async throws -> SkillDetailResponse {
        guard file == nil else { throw BotFailure.unsupported }
        return try Self.decode(SkillDetailResponse.self, try await send(.skillContent(name: name, profile: profile)))
    }

    func toggleSkill(name: String, enabled: Bool) async throws -> ToggleSkillResponse {
        try Self.decode(ToggleSkillResponse.self, try await send(.setSkill(name: name, enabled: enabled, profile: profile)))
    }

    /// `GET /api/skills`'s bare array as the app's skills: each one `disabled` when the host lists
    /// it not `enabled`, and a row without a name left out. A reply that is not an array is a
    /// failed read, not an empty Profile. The Tasks editor reads its skills through it too
    /// (`HermesCronClient.cronSkills`).
    static func skills(_ body: Data) throws -> [SkillSummary] {
        try decode([BotJSON].self, body).compactMap { row in
            guard let name = row["name"].text, !name.isEmpty else { return nil }
            return SkillSummary(name: name, category: row["category"].text, description: row["description"].text,
                                path: nil, disabled: row["enabled"].flag.map { !$0 })
        }
    }

    /// One request's body, or the failure the host's status means (`HermesCronClient.accepted`).
    /// A dropped request reads as the webui's network failure, so a cancellation is recognised as one.
    private func send(_ rest: HermesREST) async throws -> Data {
        let reply: (body: Data, status: Int)
        do { reply = try await http.reply(rest) } catch let error as URLError { throw APIError.network(underlying: error) }
        return try HermesCronClient.accepted(reply)
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ body: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: body) } catch { throw APIError.decoding(underlying: error) }
    }
}
