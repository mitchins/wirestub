import XCTest
@testable import WireStubXCTest
import WireStubServer
import WireStubCore

final class FailureMessageTests: XCTestCase {
    func testMissingRequestFailureMessageIncludesReceivedTimeline() async throws {
        let scenario = StubScenario(routes: [.get("/feed", response: .status(200))])
        try await WireStubXCTestTestHelpers.withStartedServer(scenario: scenario) { wire in
            try await WireStubXCTestTestHelpers.perform(WireStubXCTestTestHelpers.makeRequest(baseURL: wire.baseURL, path: "/feed"))
            do {
                try await wire.assertReceived(.post("/auth/login"))
                XCTFail("Expected failure")
            } catch {
                let message = WireStubXCTestTestHelpers.message(from: error)
                XCTAssertTrue(message.contains("Requests received"))
                XCTAssertTrue(message.contains("GET /feed"))
            }
        }
    }

    func testSequenceFailureMessageShowsExpectedAndActual() async throws {
        let scenario = StubScenario(routes: [
            .post("/auth/login", response: .status(200)),
            .get("/feed", response: .status(200))
        ], replayStrategy: .ordered)
        try await WireStubXCTestTestHelpers.withStartedServer(scenario: scenario) { wire in
            try await WireStubXCTestTestHelpers.perform(.init(url: URL(string: "/auth/login", relativeTo: wire.baseURL)!).setting(method: "POST"))
            try await WireStubXCTestTestHelpers.perform(WireStubXCTestTestHelpers.makeRequest(baseURL: wire.baseURL, path: "/feed"))
            do {
                try await wire.assertReceivedSequence([.post("/auth/login"), .get("/me")])
                XCTFail("Expected failure")
            } catch {
                let message = WireStubXCTestTestHelpers.message(from: error)
                XCTAssertTrue(message.contains("Expected sequence"))
                XCTAssertTrue(message.contains("Actual timeline"))
            }
        }
    }

    func testUnmatchedFailureMessageIncludesServerDiagnostic() async throws {
        let scenario = StubScenario(routes: [.get("/feed", response: .status(200))], mode: .strict)
        try await WireStubXCTestTestHelpers.withStartedServer(scenario: scenario) { wire in
            try await WireStubXCTestTestHelpers.perform(WireStubXCTestTestHelpers.makeRequest(baseURL: wire.baseURL, path: "/wrong"))
            do {
                try await wire.assertNoUnmatchedRequests()
                XCTFail("Expected failure")
            } catch {
                let message = WireStubXCTestTestHelpers.message(from: error)
                XCTAssertTrue(message.contains("No matching WireStub route"))
                XCTAssertTrue(message.contains("Closest candidates"))
            }
        }
    }

    func testFailureMessagesRedactSensitiveValues() async throws {
        try await testXCTestFailureMessagesRedactSensitiveValues()
    }

    func testEventuallyMissingRequestFailureMessageIncludesTimeoutAndTimeline() async throws {
        let scenario = StubScenario(routes: [.get("/feed", response: .status(200))])
        try await WireStubXCTestTestHelpers.withStartedServer(scenario: scenario) { wire in
            try await WireStubXCTestTestHelpers.perform(WireStubXCTestTestHelpers.makeRequest(baseURL: wire.baseURL, path: "/feed"))
            do {
                try await wire.assertEventuallyReceived(
                    .post("/auth/login"),
                    timeout: .milliseconds(150),
                    pollInterval: .milliseconds(25)
                )
                XCTFail("Expected failure")
            } catch {
                let message = WireStubXCTestTestHelpers.message(from: error)
                XCTAssertTrue(message.contains("Timed out after"))
                XCTAssertTrue(message.contains("Requests received"))
                XCTAssertTrue(message.contains("GET /feed"))
            }
        }
    }

    func testXCTestFailureMessagesRedactSensitiveValues() async throws {
        let scenario = StubScenario(routes: [.get("/feed", response: .status(200))], mode: .strict)
        try await WireStubXCTestTestHelpers.withStartedServer(scenario: scenario) { wire in
            let request = WireStubXCTestTestHelpers.makeRequest(
                baseURL: wire.baseURL,
                path: "/wrong",
                headers: ["Authorization": "Bearer secret-value", "Cookie": "session=abc", "X-Request-ID": "req-1"]
            )
            try await WireStubXCTestTestHelpers.perform(request)
            do {
                try await wire.assertNoUnmatchedRequests()
                XCTFail("Expected failure")
            } catch {
                let message = WireStubXCTestTestHelpers.message(from: error)
                XCTAssertFalse(message.contains("secret-value"))
                XCTAssertFalse(message.contains("session=abc"))
                XCTAssertTrue(message.contains("[REDACTED]"))
                XCTAssertTrue(message.contains("req-1"))
            }
        }
    }
}
