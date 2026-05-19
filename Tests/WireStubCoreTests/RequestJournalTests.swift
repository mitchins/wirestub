import XCTest
@testable import WireStubCore

final class RequestJournalTests: XCTestCase {

    func testJournalRecordsMatchedRequestsInOrder() async throws {
        let scenario = StubScenario(
            routes: [
                .get("/a", response: .status(200)),
                .get("/b", response: .status(201)),
            ],
            replayStrategy: .firstMatch
        )
        let engine = StubEngine(scenario: scenario)

        _ = await engine.handle(RequestSnapshot(method: "GET", path: "/a"))
        _ = await engine.handle(RequestSnapshot(method: "GET", path: "/b"))

        let journal = await engine.currentJournal()
        XCTAssertEqual(journal.entries.count, 2)
        XCTAssertEqual(journal.entries[0].request.path, "/a")
        XCTAssertEqual(journal.entries[1].request.path, "/b")
        XCTAssertEqual(journal.entries[0].sequenceIndex, 0)
        XCTAssertEqual(journal.entries[1].sequenceIndex, 1)
    }

    func testJournalRecordsUnmatchedRequestsInOrder() async throws {
        let scenario = StubScenario(
            routes: [.get("/expected", response: .status(200))],
            replayStrategy: .firstMatch
        )
        let engine = StubEngine(scenario: scenario)

        _ = await engine.handle(RequestSnapshot(method: "GET", path: "/unexpected"))

        let journal = await engine.currentJournal()
        XCTAssertEqual(journal.unmatchedEntries.count, 1)
        XCTAssertEqual(journal.unmatchedEntries.first?.request.path, "/unexpected")
    }

    func testJournalRecordsRouteIDAndStatus() async throws {
        let route = StubRoute.get("/status", response: .status(204))
        let scenario = StubScenario(routes: [route], replayStrategy: .firstMatch)
        let engine = StubEngine(scenario: scenario)

        _ = await engine.handle(RequestSnapshot(method: "GET", path: "/status"))

        let journal = await engine.currentJournal()
        guard case .matched(let routeID, let status) = journal.entries.first?.outcome else {
            return XCTFail("Expected matched outcome")
        }
        XCTAssertEqual(routeID, route.id)
        XCTAssertEqual(status, 204)
    }

    func testJournalCanFilterByMethodAndPath() async throws {
        let scenario = StubScenario(
            routes: [
                .get("/feed", response: .status(200)),
                .post("/events", response: .status(201)),
            ],
            replayStrategy: .firstMatch
        )
        let engine = StubEngine(scenario: scenario)

        _ = await engine.handle(RequestSnapshot(method: "GET", path: "/feed"))
        _ = await engine.handle(RequestSnapshot(method: "POST", path: "/events"))
        _ = await engine.handle(RequestSnapshot(method: "GET", path: "/feed"))

        let journal = await engine.currentJournal()
        XCTAssertEqual(journal.count(method: "GET", path: "/feed"), 2)
        XCTAssertEqual(journal.count(method: "POST", path: "/events"), 1)
    }

    func testJournalCanCountMatchingRequests() async throws {
        let scenario = StubScenario(
            routes: [
                .get("/ping", response: .status(200)),
            ],
            replayStrategy: .firstMatch
        )
        let engine = StubEngine(scenario: scenario)

        for _ in 0..<5 {
            _ = await engine.handle(RequestSnapshot(method: "GET", path: "/ping"))
        }

        let journal = await engine.currentJournal()
        XCTAssertEqual(journal.count(method: "GET", path: "/ping"), 5)
    }

    func testSeparateEnginesDoNotShareJournalOrReplayState() async throws {
        let scenario = StubScenario(
            routes: [.get("/data", response: .status(200))],
            replayStrategy: .firstMatch
        )
        let engine1 = StubEngine(scenario: scenario)
        let engine2 = StubEngine(scenario: scenario)

        _ = await engine1.handle(RequestSnapshot(method: "GET", path: "/data"))

        let journal1 = await engine1.currentJournal()
        let journal2 = await engine2.currentJournal()

        XCTAssertEqual(journal1.entries.count, 1)
        XCTAssertEqual(journal2.entries.count, 0, "Engines must not share journal state")
    }

    func testJournalRenderedTimelineRedactsSensitiveValues() async throws {
        let scenario = StubScenario(routes: [.get("/known", response: .status(200))], mode: .strict)
        let engine = StubEngine(scenario: scenario)

        _ = await engine.handle(
            RequestSnapshot(
                method: "GET",
                path: "/wrong",
                queryItems: [QueryItem(name: "token", value: "secret-token")],
                headers: ["Authorization": "Bearer top-secret"]
            )
        )

        let journal = await engine.currentJournal()
        let rendered = journal.renderedTimeline()
        XCTAssertTrue(rendered.contains("[REDACTED]"))
        XCTAssertFalse(rendered.contains("top-secret"))
        XCTAssertFalse(rendered.contains("secret-token"))
    }
}
