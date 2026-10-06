import XCTest
@testable import HermesMobile

/// Skills on a Hermes host (#1069): `HermesSkillsClient` against a scripted host whose replies
/// are the shapes `scripts/local-hermes` answered at the pin (0.21.5, ca678285).
@MainActor final class HermesSkillsClientTests: XCTestCase {
    override func tearDown() {
        HermesHostFixture.reset()
        super.tearDown()
    }

    func testTheListIsTheProfilesBareArrayWithEnabledReadAsDisabled() async throws {
        let client = Self.client { request in
            request.url?.path == "/api/skills" ? .json(200, .array([
                .object(["name": .string("apple-notes"), "description": .string("Manage Apple Notes."),
                         "category": .string("apple"), "enabled": .bool(true), "usage": .number(3),
                         "provenance": .string("bundled"), "future_field": .object(["x": .number(1)])]),
                .object(["name": .string("arxiv"), "description": .null, "category": .string("research"),
                         "enabled": .bool(false), "usage": .number(0), "provenance": .string("hub")]),
                .object(["description": .string("A row without a name")])
            ])) : nil
        }

        let response = try await client.skills()
        let skills = try XCTUnwrap(response.skills)

        XCTAssertEqual(skills.map(\.name), ["apple-notes", "arxiv"])
        XCTAssertEqual(skills.map(\.disabled), [false, true])
        XCTAssertEqual(skills.map(\.category), ["apple", "research"])
        XCTAssertEqual(skills.map(\.description), ["Manage Apple Notes.", nil])
        let request = try XCTUnwrap(HermesHostFixture.requests.last)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.query, "profile=research")
    }

    func testAListThatIsNotAnArrayIsAFailedReadNotAnEmptyProfile() async throws {
        let client = Self.client { request in
            request.url?.path == "/api/skills" ? .json(200, .object([
                "skills": .array([.object(["name": .string("arxiv"), "enabled": .bool(true)])])
            ])) : nil
        }

        do {
            let response = try await client.skills()
            XCTFail("Expected a failed read, got \(response.skills?.count ?? 0) skills")
        } catch {
            guard case APIError.decoding = error else { return XCTFail("Expected a decoding failure, got \(error)") }
        }
    }

    func testATogglePutsTheNameStateAndProfileInTheBody() async throws {
        let client = Self.client { request in
            request.url?.path == "/api/skills/toggle" && request.httpMethod == "PUT"
                ? .json(200, .object(["ok": .bool(true), "name": .string("arxiv"), "enabled": .bool(false)])) : nil
        }

        let response = try await client.toggleSkill(name: "arxiv", enabled: false)

        XCTAssertEqual(response.enabled, false)
        let request = try XCTUnwrap(HermesHostFixture.requests.last)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.path, "/api/skills/toggle")
        XCTAssertNil(request.url?.query, "The body's Profile wins on the host, so it goes only there")
        XCTAssertEqual(HermesCronFixture.body(request), .object([
            "name": .string("arxiv"), "enabled": .bool(false), "profile": .string("research")
        ]))
    }

    func testContentIsTheProfilesSkillMdWithoutTheHostPath() async throws {
        let hostPath = "/Users/someone/.hermes/profiles/research/skills/research/arxiv/SKILL.md"
        let client = Self.client { request in
            request.url?.path == "/api/skills/content" ? .json(200, .object([
                "name": .string("arxiv"), "content": .string("---\nname: arxiv\n---\n# arXiv"), "path": .string(hostPath)
            ])) : nil
        }

        let detail = try await client.skillContent(name: "arxiv", file: nil)

        XCTAssertEqual(detail.content, "---\nname: arxiv\n---\n# arXiv")
        XCTAssertNil(detail.linkedFiles)
        XCTAssertFalse(String(describing: detail).contains(hostPath), "The host path is never kept")
        let request = try XCTUnwrap(HermesHostFixture.requests.last)
        let query = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(query, [URLQueryItem(name: "name", value: "arxiv"), URLQueryItem(name: "profile", value: "research")])
    }

    func testARefusedToggleCarriesTheHostsDetail() async throws {
        let client = Self.client { request in
            request.url?.path == "/api/skills/toggle"
                ? .json(404, .object(["detail": .string("Profile 'research' does not exist.")])) : nil
        }

        do {
            _ = try await client.toggleSkill(name: "arxiv", enabled: false)
            XCTFail("Expected the host's refusal")
        } catch {
            XCTAssertEqual(error.localizedDescription, "The server rejected the request: Profile 'research' does not exist.")
        }
    }

    func testAMissingSkillReadsAsNotFound() async throws {
        let client = Self.client { request in
            request.url?.path == "/api/skills/content"
                ? .json(404, .object(["detail": .string("Skill 'arxiv' not found.")])) : nil
        }

        do {
            _ = try await client.skillContent(name: "arxiv", file: nil)
            XCTFail("Expected the host's 404")
        } catch {
            XCTAssertEqual(error.localizedDescription, "The server rejected the request: Skill 'arxiv' not found.")
        }
    }

    /// A client for the `research` Profile on a scripted host.
    private static func client(_ script: @escaping (URLRequest) -> HermesHostFixture.Reply?) -> HermesSkillsClient {
        let record = BotConnection(id: UUID(), name: "Host", address: URL(string: "https://hermes.example")!,
                                   username: "user", password: "secret")
        return HermesSkillsClient(http: HermesConnection(connection: record, configuration: HermesHostFixture.configuration(script)),
                                  profile: "research")
    }
}
