import Foundation
import WatchShared
import XCTest
@testable import HermesMobile

/// The iPhone side of the watch glances: server JSON → wrist-shaped glance
/// values. Decoded with the same snake-case strategy `APIClient` uses.
final class WatchCompanionGlanceMappingTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: Data(json.utf8))
    }

    // MARK: Tasks

    func testTaskGlanceTakesRunningFromCronStatusAndKeepsTimesAndFailure() throws {
        let job = try decode(CronJob.self, #"""
        {"job_id":"digest","name":"Morning digest","schedule":{"kind":"cron","expr":"0 8 * * *"},
         "enabled":true,"state":"scheduled","next_run_at":1700050000,"last_run_at":1699990000,
         "last_status":"error","last_error":"Timed out after 300s\nTraceback (most recent call last):"}
        """#)

        let glance = try XCTUnwrap(APIClientWatchPhoneBackend.taskGlance(from: job, runningJobIDs: ["digest"]))

        XCTAssertTrue(glance.running)
        XCTAssertTrue(glance.enabled)
        XCTAssertEqual(glance.lastResult, "error")
        XCTAssertEqual(glance.failureSummary, "Timed out after 300s")
        XCTAssertEqual(glance.nextRunAt, Date(timeIntervalSince1970: 1_700_050_000))
        XCTAssertEqual(glance.lastRunAt, Date(timeIntervalSince1970: 1_699_990_000))
        // The humanized schedule, not the raw cron expression.
        XCTAssertNotEqual(glance.schedule, "0 8 * * *")
    }

    func testPausedTaskIsNotEnabledAndHasNoNextRun() throws {
        let job = try decode(CronJob.self, #"""
        {"job_id":"prices","name":"Price watch","enabled":false,"state":"paused","next_run_at":1700050000}
        """#)

        let glance = try XCTUnwrap(APIClientWatchPhoneBackend.taskGlance(from: job, runningJobIDs: []))

        XCTAssertFalse(glance.enabled)
        XCTAssertFalse(glance.running)
        XCTAssertNil(glance.nextRunAt)
    }

    // MARK: Kanban

    func testKanbanGlanceUsesTheIPhoneBoardBeforeAnEmptyActiveBoard() throws {
        let boards = try decode(KanbanBoardsResponse.self, #"""
        {"current":"default","boards":[
          {"slug":"default","name":"Default","is_current":true,"total":0},
          {"slug":"studio","name":"Studio","total":4},
          {"slug":"archive","name":"Archive","total":0}
        ]}
        """#)

        XCTAssertEqual(
            APIClientWatchPhoneBackend.boardSlugsToTry(in: boards, preferred: "studio"),
            ["studio", "default"]
        )
        XCTAssertEqual(
            APIClientWatchPhoneBackend.boardSlugsToTry(in: boards, preferred: nil),
            ["default", "studio"]
        )
    }

    func testKanbanHarvestReadsTasksWhenTheColumnModelMissesThem() {
        let data = Data(#"""
        {"lanes":[{"name":"todo","items":[{"task_id":"t_9","title":"Ship the watch","status":"todo"}]}]}
        """#.utf8)
        let cards = APIClientWatchPhoneBackend.harvestedCards(from: data, limit: 10)
        XCTAssertEqual(cards.map(\.id), ["t_9"])
        XCTAssertEqual(cards.first?.title, "Ship the watch")
        XCTAssertEqual(cards.first?.status, "todo")
    }

    func testKanbanCardsCarryStatusKeysAndSkipArchivedAndIDlessCards() throws {
        let snapshot = try decode(KanbanBoardSnapshot.self, #"""
        {"columns":[
          {"name":"todo","tasks":[{"id":"C1","title":"Write notes","status":"todo","assignee":"default","priority":2,"body":"**Body**","tenant":"studio","comment_count":3,"age_seconds":3700,"skills":["swift"],"link_counts":{"parents":1,"children":1}}]},
          {"name":"running","tasks":[{"title":"No id","status":"running"},{"id":"C2","title":"Ship","status":"running"}]},
          {"name":"archived","tasks":[{"id":"C3","title":"Old","status":"archived"}]}
        ]}
        """#)

        let cards = APIClientWatchPhoneBackend.kanbanCards(from: snapshot, limit: 10)

        XCTAssertEqual(cards.map(\.id), ["C1", "C2"])
        XCTAssertEqual(cards.map(\.status), ["todo", "running"])
        XCTAssertEqual(cards.first?.assignee, "default")
        XCTAssertEqual(cards.first?.priority, 2)
        XCTAssertEqual(cards.first?.body, "**Body**")
        XCTAssertEqual(cards.first?.tenant, "studio")
        XCTAssertEqual(cards.first?.commentCount, 3)
        XCTAssertEqual(cards.first?.linkCount, 2)
        XCTAssertEqual(cards.first?.ageSeconds, 3_700)
        XCTAssertEqual(cards.first?.skills, ["swift"])
    }

    // MARK: Memory

    func testMemoryIsSplitIntoEntriesWithoutTheDelimiter() throws {
        let response = try decode(MemoryResponse.self, #"""
        {"memory":"Prefers short replies.\n§\nShips from the Mac mini.",
         "user":"**Name:** Aaryan Guglani\n§\n**Email:** guglaniaaryan@gmail.com\n§\n**Timezone:** GMT+5:30",
         "soul":"Persona text"}
        """#)

        let glances = APIClientWatchPhoneBackend.memoryGlances(from: response)

        XCTAssertEqual(glances.map(\.section), ["memory", "user"])
        let user = try XCTUnwrap(glances.last)
        XCTAssertEqual(WatchMemoryProjection.entries(in: user.text), [
            "**Name:** Aaryan Guglani",
            "**Email:** guglaniaaryan@gmail.com",
            "**Timezone:** GMT+5:30",
        ])
        XCTAssertFalse(user.isTruncated)
    }

    func testPersonaFillsInOnlyWhenTheOtherSectionsAreEmpty() throws {
        let response = try decode(MemoryResponse.self, #"{"memory":"  ","user":null,"soul":"Calm and direct."}"#)

        XCTAssertEqual(APIClientWatchPhoneBackend.memoryGlances(from: response).map(\.section), ["soul"])
    }

    // MARK: Usage

    func testUsageCarriesPerModelCostAndDailyTokensOldestFirst() throws {
        let response = try decode(InsightsResponse.self, #"""
        {"period_days":7,"total_sessions":3,"total_cost":2.5,"total_tokens":1000,
         "models":[{"model":"cheap","total_tokens":900,"cost":0.5,"sessions":2},{"model":"pricey","input_tokens":60,"output_tokens":40,"cost":2.0,"sessions":1}],
         "daily_tokens":[{"date":"2026-10-03","input_tokens":5,"output_tokens":5},{"date":"2026-10-01","input_tokens":1,"output_tokens":0}]}
        """#)

        let glance = APIClientWatchPhoneBackend.usageGlance(from: response, window: 7)

        XCTAssertEqual(glance.days, 7)
        XCTAssertEqual(glance.modelUsage.map(\.name), ["pricey", "cheap"])
        XCTAssertEqual(glance.modelUsage.first?.totalTokens, 100)
        XCTAssertEqual(glance.dailyTokens, [1, 10])
    }
}
