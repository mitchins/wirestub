import XCTest
@testable import WireStubCore

final class StubEngineOrderedReplayTests: XCTestCase {

    func testOrderedReplayRequiresTheNextExpectedRequest() async throws {
        let scenario = StubScenario(
            routes: [
                .post("/auth/login", response: .status(200)),
                .get("/me", response: .status(200)),
            ],
            replayStrategy: .ordered
        )
        let engine = StubEngine(scenario: scenario)

        // Skip the first expected route and send /me first
        let result = await engine.handle(RequestSnapshot(method: "GET", path: "/me"))

        guard case .unmatched(let diagnostic) = result else {
            return XCTFail("Ordered replay must reject out-of-order requests")
        }
        XCTAssertEqual(diagnostic.nextExpectedRouteID, scenario.routes[0].id)
    }

    func testOrderedReplayAllowsRepeatedSamePathWithDifferentResponses() async throws {
        let scenario = StubScenario(
            routes: [
                .get("/feed", response: .status(200)),
                .get("/feed", response: .status(401)),
                .get("/feed", response: .status(200)),
            ],
            replayStrategy: .ordered
        )
        let engine = StubEngine(scenario: scenario)

        let r1 = await engine.handle(RequestSnapshot(method: "GET", path: "/feed"))
        let r2 = await engine.handle(RequestSnapshot(method: "GET", path: "/feed"))
        let r3 = await engine.handle(RequestSnapshot(method: "GET", path: "/feed"))

        guard case .matched(let s1, _) = r1,
              case .matched(let s2, _) = r2,
              case .matched(let s3, _) = r3 else {
            return XCTFail("All three /feed requests should match in order")
        }
        XCTAssertEqual(s1.status, 200)
        XCTAssertEqual(s2.status, 401)
        XCTAssertEqual(s3.status, 200)
    }

    func testOrderedReplayDoesNotAdvanceCursorOnMismatch() async throws {
        let scenario = StubScenario(
            routes: [
                .post("/auth/login", response: .status(200)),
                .get("/me", response: .status(200)),
            ],
            replayStrategy: .ordered
        )
        let engine = StubEngine(scenario: scenario)

        // Send wrong request — cursor must stay at index 0
        _ = await engine.handle(RequestSnapshot(method: "GET", path: "/wrong"))

        // Now send the correct first request — should match
        let result = await engine.handle(RequestSnapshot(method: "POST", path: "/auth/login"))
        guard case .matched(let response, _) = result else {
            return XCTFail("Cursor must not advance on mismatch; correct request should still match")
        }
        XCTAssertEqual(response.status, 200)
    }

    func testOrderedReplayReportsNextExpectedRouteOnMismatch() async throws {
        let firstRoute = StubRoute.post("/auth/login", response: .status(200))
        let scenario = StubScenario(
            routes: [firstRoute, .get("/me", response: .status(200))],
            replayStrategy: .ordered
        )
        let engine = StubEngine(scenario: scenario)

        let result = await engine.handle(RequestSnapshot(method: "GET", path: "/me"))

        guard case .unmatched(let diagnostic) = result else {
            return XCTFail("Expected unmatched")
        }
        XCTAssertEqual(diagnostic.nextExpectedRouteID, firstRoute.id)
        XCTAssertTrue(diagnostic.render().contains(firstRoute.id))
    }
}
