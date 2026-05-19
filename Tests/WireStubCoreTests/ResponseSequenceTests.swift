import XCTest
@testable import WireStubCore

final class ResponseSequenceTests: XCTestCase {

    func testSequenceProviderReturnsResponsesInOrder() async throws {
        let route = StubRoute.sequence(
            method: "GET",
            path: "/items",
            responses: [.status(200), .status(201), .status(202)]
        )
        let scenario = StubScenario(routes: [route], replayStrategy: .firstMatch)
        let engine = StubEngine(scenario: scenario)

        let r1 = await engine.handle(RequestSnapshot(method: "GET", path: "/items"))
        let r2 = await engine.handle(RequestSnapshot(method: "GET", path: "/items"))
        let r3 = await engine.handle(RequestSnapshot(method: "GET", path: "/items"))

        guard case .matched(let s1, _) = r1,
              case .matched(let s2, _) = r2,
              case .matched(let s3, _) = r3 else {
            return XCTFail("All three responses should be matched")
        }
        XCTAssertEqual(s1.status, 200)
        XCTAssertEqual(s2.status, 201)
        XCTAssertEqual(s3.status, 202)
    }

    func testSequenceProviderFailsWhenExhaustedByDefault() async throws {
        let route = StubRoute.sequence(
            method: "GET",
            path: "/items",
            responses: [.status(200)],
            exhaustion: .fail
        )
        let scenario = StubScenario(routes: [route], replayStrategy: .firstMatch)
        let engine = StubEngine(scenario: scenario)

        _ = await engine.handle(RequestSnapshot(method: "GET", path: "/items"))
        let second = await engine.handle(RequestSnapshot(method: "GET", path: "/items"))

        guard case .unmatched = second else {
            return XCTFail("Sequence exhausted with .fail should return unmatched")
        }
    }

    func testSequenceProviderCanRepeatLastWhenConfigured() async throws {
        let route = StubRoute.sequence(
            method: "GET",
            path: "/items",
            responses: [.status(200)],
            exhaustion: .repeatLast
        )
        let scenario = StubScenario(routes: [route], replayStrategy: .firstMatch)
        let engine = StubEngine(scenario: scenario)

        _ = await engine.handle(RequestSnapshot(method: "GET", path: "/items"))
        let second = await engine.handle(RequestSnapshot(method: "GET", path: "/items"))

        guard case .matched(let response, _) = second else {
            return XCTFail("repeatLast should return last response after exhaustion")
        }
        XCTAssertEqual(response.status, 200)
    }

    func testSequenceStateIsPerRouteNotGlobal() async throws {
        let routeA = StubRoute.sequence(
            method: "GET",
            path: "/a",
            responses: [.status(200), .status(201)]
        )
        let routeB = StubRoute.sequence(
            method: "GET",
            path: "/b",
            responses: [.status(400), .status(401)]
        )
        let scenario = StubScenario(routes: [routeA, routeB], replayStrategy: .firstMatch)
        let engine = StubEngine(scenario: scenario)

        let a1 = await engine.handle(RequestSnapshot(method: "GET", path: "/a"))
        let b1 = await engine.handle(RequestSnapshot(method: "GET", path: "/b"))
        let a2 = await engine.handle(RequestSnapshot(method: "GET", path: "/a"))
        let b2 = await engine.handle(RequestSnapshot(method: "GET", path: "/b"))

        guard case .matched(let sa1, _) = a1, case .matched(let sb1, _) = b1,
              case .matched(let sa2, _) = a2, case .matched(let sb2, _) = b2 else {
            return XCTFail("All requests should match")
        }
        XCTAssertEqual(sa1.status, 200)
        XCTAssertEqual(sb1.status, 400)
        XCTAssertEqual(sa2.status, 201)
        XCTAssertEqual(sb2.status, 401)
    }
}
