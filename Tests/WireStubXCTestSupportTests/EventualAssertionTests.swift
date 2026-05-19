import XCTest
@testable import WireStubXCTest
import WireStubServer
import WireStubCore

final class EventualAssertionTests: XCTestCase {
    func testAssertEventuallyReceivedWaitsForDelayedRequest() async throws {
        let scenario = StubScenario(routes: [.post("/auth/login", response: .status(200))])

        try await WireStubXCTestTestHelpers.withStartedServer(scenario: scenario) { wire in
            let task = Task<Void, Error> {
                try await Task.sleep(for: .milliseconds(120))
                try await WireStubXCTestTestHelpers.perform(
                    WireStubXCTestTestHelpers.makeRequest(baseURL: wire.baseURL, method: "POST", path: "/auth/login")
                )
            }

            try await wire.assertEventuallyReceived(
                .post("/auth/login"),
                timeout: .seconds(2),
                pollInterval: .milliseconds(50)
            )
            try await task.value
        }
    }

    func testAssertEventuallyReceivedCountWaitsForExactCount() async throws {
        let scenario = StubScenario(
            routes: [
                .get("/feed", response: .status(200)),
                .get("/feed", response: .status(200)),
            ],
            replayStrategy: .ordered
        )

        try await WireStubXCTestTestHelpers.withStartedServer(scenario: scenario) { wire in
            let task = Task<Void, Error> {
                try await Task.sleep(for: .milliseconds(60))
                try await WireStubXCTestTestHelpers.perform(WireStubXCTestTestHelpers.makeRequest(baseURL: wire.baseURL, path: "/feed"))
                try await Task.sleep(for: .milliseconds(60))
                try await WireStubXCTestTestHelpers.perform(WireStubXCTestTestHelpers.makeRequest(baseURL: wire.baseURL, path: "/feed"))
            }

            try await wire.assertEventuallyReceived(
                .get("/feed"),
                count: 2,
                timeout: .seconds(2),
                pollInterval: .milliseconds(50)
            )
            try await task.value
        }
    }

    func testAssertEventuallyReceivedSequenceWaitsForFullTimeline() async throws {
        let scenario = StubScenario(
            routes: [
                .post("/auth/login", response: .status(200)),
                .get("/me", response: .status(200)),
                .get("/feed", response: .status(200)),
            ],
            replayStrategy: .ordered
        )

        try await WireStubXCTestTestHelpers.withStartedServer(scenario: scenario) { wire in
            let task = Task<Void, Error> {
                try await Task.sleep(for: .milliseconds(40))
                try await WireStubXCTestTestHelpers.perform(
                    WireStubXCTestTestHelpers.makeRequest(baseURL: wire.baseURL, method: "POST", path: "/auth/login")
                )
                try await Task.sleep(for: .milliseconds(40))
                try await WireStubXCTestTestHelpers.perform(WireStubXCTestTestHelpers.makeRequest(baseURL: wire.baseURL, path: "/me"))
                try await Task.sleep(for: .milliseconds(40))
                try await WireStubXCTestTestHelpers.perform(WireStubXCTestTestHelpers.makeRequest(baseURL: wire.baseURL, path: "/feed"))
            }

            try await wire.assertEventuallyReceivedSequence(
                [.post("/auth/login"), .get("/me"), .get("/feed")],
                timeout: .seconds(2),
                pollInterval: .milliseconds(50)
            )
            try await task.value
        }
    }

    func testAssertEventuallyNoUnmatchedRequestsFailsWhenUnmatchedRequestExists() async throws {
        let scenario = StubScenario(routes: [.get("/known", response: .status(200))], mode: .strict)

        try await WireStubXCTestTestHelpers.withStartedServer(scenario: scenario) { wire in
            try await WireStubXCTestTestHelpers.perform(
                WireStubXCTestTestHelpers.makeRequest(baseURL: wire.baseURL, path: "/missing")
            )

            do {
                try await wire.assertEventuallyNoUnmatchedRequests(
                    timeout: .seconds(1),
                    pollInterval: .milliseconds(50)
                )
                XCTFail("Expected eventual unmatched assertion to fail")
            } catch {
                let message = WireStubXCTestTestHelpers.message(from: error)
                XCTAssertTrue(message.contains("Timed out after"))
                XCTAssertTrue(message.contains("/missing"))
            }
        }
    }

    func testAssertEventuallyScenarioCompleteWaitsForOrderedConsumption() async throws {
        let scenario = StubScenario(
            routes: [
                .post("/auth/login", response: .status(200)),
                .get("/feed", response: .status(200)),
            ],
            replayStrategy: .ordered
        )

        try await WireStubXCTestTestHelpers.withStartedServer(scenario: scenario) { wire in
            let task = Task<Void, Error> {
                try await Task.sleep(for: .milliseconds(80))
                try await WireStubXCTestTestHelpers.perform(
                    WireStubXCTestTestHelpers.makeRequest(baseURL: wire.baseURL, method: "POST", path: "/auth/login")
                )
                try await Task.sleep(for: .milliseconds(80))
                try await WireStubXCTestTestHelpers.perform(WireStubXCTestTestHelpers.makeRequest(baseURL: wire.baseURL, path: "/feed"))
            }

            try await wire.assertEventuallyScenarioComplete(
                timeout: .seconds(2),
                pollInterval: .milliseconds(50)
            )
            try await task.value
        }
    }

    func testAssertEventuallyScenarioCompletePreservesUnsupportedErrorForFirstMatch() async throws {
        let scenario = StubScenario(routes: [.get("/feed", response: .status(200))], replayStrategy: .firstMatch)

        try await WireStubXCTestTestHelpers.withStartedServer(scenario: scenario) { wire in
            await XCTAssertThrowsErrorAsync(
                try await wire.assertEventuallyScenarioComplete(
                    timeout: .seconds(1),
                    pollInterval: .milliseconds(50)
                )
            ) { error in
                XCTAssertEqual(
                    error as? WireStubXCTestError,
                    .scenarioCompletionUnsupported(replayStrategy: .firstMatch)
                )
            }
        }
    }

    func testAssertEventuallyNoUnexpectedRequestsAliasesNoUnmatched() async throws {
        let scenario = StubScenario(routes: [.get("/known", response: .status(200))])

        try await WireStubXCTestTestHelpers.withStartedServer(scenario: scenario) { wire in
            try await wire.assertEventuallyNoUnexpectedRequests(
                timeout: .seconds(1),
                pollInterval: .milliseconds(50)
            )
        }
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: @autoclosure () async throws -> Void,
    _ errorHandler: (Error) -> Void
) async {
    do {
        try await expression()
        XCTFail("Expected error")
    } catch {
        errorHandler(error)
    }
}
