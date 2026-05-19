import XCTest
@testable import WireStubXCTest
import WireStubServer
import WireStubCore

final class ScenarioAssertionTests: XCTestCase {
    func testAssertAllExpectedRoutesWereConsumedInOrderedReplay() async throws {
        try await testAssertScenarioCompletePassesWhenAllOrderedRoutesConsumed()
    }

    func testAssertScenarioCompletePassesWhenAllOrderedRoutesConsumed() async throws {
        let route1 = StubRoute.post("/auth/login", response: .status(200))
        let route2 = StubRoute.get("/feed", response: .status(200))
        let scenario = StubScenario(routes: [route1, route2], replayStrategy: .ordered)

        try await WireStubXCTestTestHelpers.withStartedServer(scenario: scenario) { wire in
            try await WireStubXCTestTestHelpers.perform(.init(url: URL(string: "/auth/login", relativeTo: wire.baseURL)!).setting(method: "POST"))
            try await WireStubXCTestTestHelpers.perform(WireStubXCTestTestHelpers.makeRequest(baseURL: wire.baseURL, path: "/feed"))
            try await wire.assertScenarioComplete()
        }
    }

    func testAssertScenarioCompleteFailsWhenOrderedRouteUnconsumed() async throws {
        let scenario = StubScenario(
            routes: [.post("/auth/login", response: .status(200)), .get("/feed", response: .status(200))],
            replayStrategy: .ordered
        )

        try await WireStubXCTestTestHelpers.withStartedServer(scenario: scenario) { wire in
            try await WireStubXCTestTestHelpers.perform(.init(url: URL(string: "/auth/login", relativeTo: wire.baseURL)!).setting(method: "POST"))
            do {
                try await wire.assertScenarioComplete()
                XCTFail("Expected failure")
            } catch {
                XCTAssertTrue(WireStubXCTestTestHelpers.message(from: error).contains("Missing route IDs"))
            }
        }
    }

    func testAssertScenarioCompleteTracksRepeatedIdenticalRoutesByRouteID() async throws {
        let first = StubRoute.get("/feed", response: .status(200))
        let second = StubRoute.get("/feed", response: .status(201))
        let scenario = StubScenario(routes: [first, second], replayStrategy: .ordered)

        try await WireStubXCTestTestHelpers.withStartedServer(scenario: scenario) { wire in
            try await WireStubXCTestTestHelpers.perform(WireStubXCTestTestHelpers.makeRequest(baseURL: wire.baseURL, path: "/feed"))
            do {
                try await wire.assertScenarioComplete()
                XCTFail("Expected failure")
            } catch {
                let message = WireStubXCTestTestHelpers.message(from: error)
                XCTAssertTrue(message.contains(second.id))
            }
        }
    }

    func testAssertScenarioCompleteThrowsClearErrorForFirstMatch() async throws {
        let scenario = StubScenario(routes: [.get("/feed", response: .status(200))], replayStrategy: .firstMatch)

        try await WireStubXCTestTestHelpers.withStartedServer(scenario: scenario) { wire in
            do {
                try await wire.assertScenarioComplete()
                XCTFail("Expected unsupported error")
            } catch {
                XCTAssertEqual(error as? WireStubXCTestError, .scenarioCompletionUnsupported(replayStrategy: .firstMatch))
            }
        }
    }

    func testAssertScenarioCompleteHandlesSequenceRoutesDeterministically() async throws {
        let route = StubRoute.sequence(method: "GET", path: "/feed", responses: [.status(200), .status(201)])
        let scenario = StubScenario(routes: [route], replayStrategy: .ordered)

        try await WireStubXCTestTestHelpers.withStartedServer(scenario: scenario) { wire in
            try await WireStubXCTestTestHelpers.perform(WireStubXCTestTestHelpers.makeRequest(baseURL: wire.baseURL, path: "/feed"))
            try await wire.assertScenarioComplete()
        }
    }

    func testAssertNoUnexpectedRequests() async throws {
        let scenario = StubScenario(routes: [.get("/feed", response: .status(200))])
        try await WireStubXCTestTestHelpers.withStartedServer(scenario: scenario) { wire in
            try await WireStubXCTestTestHelpers.perform(WireStubXCTestTestHelpers.makeRequest(baseURL: wire.baseURL, path: "/feed"))
            try await wire.assertNoUnexpectedRequests()
        }
    }

    func testAssertRouteWasConsumed() async throws {
        let route = StubRoute.get("/feed", response: .status(200))
        let scenario = StubScenario(routes: [route])
        try await WireStubXCTestTestHelpers.withStartedServer(scenario: scenario) { wire in
            try await WireStubXCTestTestHelpers.perform(WireStubXCTestTestHelpers.makeRequest(baseURL: wire.baseURL, path: "/feed"))
            try await wire.assertRouteConsumed(route.id)
        }
    }

    func testAssertRouteWasNotConsumed() async throws {
        let route = StubRoute.get("/feed", response: .status(200))
        let scenario = StubScenario(routes: [route])
        try await WireStubXCTestTestHelpers.withStartedServer(scenario: scenario) { wire in
            try await wire.assertRouteNotConsumed(route.id)
        }
    }
}
