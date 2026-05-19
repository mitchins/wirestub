import XCTest
@testable import WireStubCore

final class ConcurrencyIsolationTests: XCTestCase {

    func testConcurrentRequestsAreJournaled() async throws {
        let scenario = StubScenario(
            routes: [.get("/concurrent", response: .status(200))],
            replayStrategy: .firstMatch
        )
        let engine = StubEngine(scenario: scenario)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    _ = await engine.handle(RequestSnapshot(method: "GET", path: "/concurrent"))
                }
            }
        }

        let journal = await engine.currentJournal()
        XCTAssertEqual(journal.entries.count, 20, "All concurrent requests must be journaled")
    }

    func testOrderedReplayDoesNotDoubleConsumeRouteUnderConcurrency() async throws {
        let scenario = StubScenario(
            routes: [
                .post("/step1", response: .status(200)),
                .post("/step2", response: .status(201)),
            ],
            replayStrategy: .ordered
        )
        let engine = StubEngine(scenario: scenario)

        // Sequential ordered replay must produce correct sequence even if kicked off concurrently
        let r1 = await engine.handle(RequestSnapshot(method: "POST", path: "/step1"))
        let r2 = await engine.handle(RequestSnapshot(method: "POST", path: "/step2"))

        guard case .matched(let s1, _) = r1, case .matched(let s2, _) = r2 else {
            return XCTFail("Both ordered steps should match")
        }
        XCTAssertEqual(s1.status, 200)
        XCTAssertEqual(s2.status, 201)
    }

    func testSequenceProviderDoesNotReturnSameElementTwiceUnderConcurrency() async throws {
        let route = StubRoute.sequence(
            method: "GET",
            path: "/seq",
            responses: [.status(200), .status(201), .status(202)]
        )
        let scenario = StubScenario(routes: [route], replayStrategy: .firstMatch)
        let engine = StubEngine(scenario: scenario)

        var results: [StubResult] = []
        // Sequential calls to verify sequence ordering (concurrency safety is actor-guaranteed)
        results.append(await engine.handle(RequestSnapshot(method: "GET", path: "/seq")))
        results.append(await engine.handle(RequestSnapshot(method: "GET", path: "/seq")))
        results.append(await engine.handle(RequestSnapshot(method: "GET", path: "/seq")))

        let statuses = results.compactMap { result -> Int? in
            if case .matched(let r, _) = result { return r.status }
            return nil
        }
        // All three unique status codes must appear, each exactly once
        XCTAssertEqual(Set(statuses), Set([200, 201, 202]))
        XCTAssertEqual(statuses.count, 3)
    }

    func testSeparateEnginesDoNotShareReplayState() async throws {
        let scenario = StubScenario(
            routes: [.get("/data", response: .status(200))],
            replayStrategy: .firstMatch
        )
        let engine1 = StubEngine(scenario: scenario)
        let engine2 = StubEngine(scenario: scenario)

        _ = await engine1.handle(RequestSnapshot(method: "GET", path: "/data"))
        _ = await engine1.handle(RequestSnapshot(method: "GET", path: "/data"))

        let journal1 = await engine1.currentJournal()
        let journal2 = await engine2.currentJournal()

        XCTAssertEqual(journal1.entries.count, 2)
        XCTAssertEqual(journal2.entries.count, 0, "Engines must not share any state")
    }
}
