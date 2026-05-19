import XCTest
@testable import WireStubXCTest
import WireStubServer
import WireStubCore

final class JournalAssertionTests: XCTestCase {
    func testAssertReceivedPassesWhenRequestExists() async throws {
        let scenario = StubScenario(routes: [.post("/auth/login", response: .status(200))])
        try await WireStubXCTestTestHelpers.withStartedServer(scenario: scenario) { wire in
            try await WireStubXCTestTestHelpers.perform(.init(url: URL(string: "/auth/login", relativeTo: wire.baseURL)!).setting(method: "POST"))
            try await wire.assertReceived(.post("/auth/login"))
        }
    }

    func testAssertReceivedFailsWhenRequestMissing() async throws {
        let scenario = StubScenario(routes: [.get("/feed", response: .status(200))])
        try await WireStubXCTestTestHelpers.withStartedServer(scenario: scenario) { wire in
            do {
                try await wire.assertReceived(.post("/auth/login"))
                XCTFail("Expected failure")
            } catch {
                let message = WireStubXCTestTestHelpers.message(from: error)
                XCTAssertTrue(message.contains("POST /auth/login"))
                XCTAssertTrue(message.contains("Requests received"))
            }
        }
    }

    func testAssertReceivedCountPasses() async throws {
        let scenario = StubScenario(routes: [
            .get("/feed", response: .status(200)),
            .get("/feed", response: .status(200))
        ], replayStrategy: .ordered)
        try await WireStubXCTestTestHelpers.withStartedServer(scenario: scenario) { wire in
            try await WireStubXCTestTestHelpers.perform(WireStubXCTestTestHelpers.makeRequest(baseURL: wire.baseURL, path: "/feed"))
            try await WireStubXCTestTestHelpers.perform(WireStubXCTestTestHelpers.makeRequest(baseURL: wire.baseURL, path: "/feed"))
            try await wire.assertReceived(.get("/feed"), count: 2)
        }
    }

    func testAssertReceivedCountFailsWithUsefulMessage() async throws {
        let scenario = StubScenario(routes: [.get("/feed", response: .status(200))])
        try await WireStubXCTestTestHelpers.withStartedServer(scenario: scenario) { wire in
            try await WireStubXCTestTestHelpers.perform(WireStubXCTestTestHelpers.makeRequest(baseURL: wire.baseURL, path: "/feed"))
            do {
                try await wire.assertReceived(.get("/feed"), count: 2)
                XCTFail("Expected failure")
            } catch {
                let message = WireStubXCTestTestHelpers.message(from: error)
                XCTAssertTrue(message.contains("Expected 2 occurrences"))
                XCTAssertTrue(message.contains("actual 1"))
            }
        }
    }

    func testAssertReceivedCanMatchHeadersAndQueryItems() async throws {
        let scenario = StubScenario(
            routes: [
                .get(
                    "/feed",
                    matching: .init(
                        queryItems: [QueryItem(name: "page", value: "1")],
                        headers: ["Authorization": "Bearer abc"]
                    ),
                    response: .status(200)
                ),
            ]
        )
        try await WireStubXCTestTestHelpers.withStartedServer(scenario: scenario) { wire in
            try await WireStubXCTestTestHelpers.perform(
                WireStubXCTestTestHelpers.makeRequest(
                    baseURL: wire.baseURL,
                    path: "/feed?page=1&source=test",
                    headers: ["Authorization": "Bearer abc"]
                )
            )

            try await wire.assertReceived(
                .get(
                    "/feed",
                    queryItems: [QueryItem(name: "page", value: "1")],
                    headers: ["Authorization": "Bearer abc"]
                )
            )
        }
    }

    func testAssertReceivedCanMatchCanonicalJSONBody() async throws {
        let requestBody = #"{"b":2,"a":1}"#.data(using: .utf8)!
        let scenario = StubScenario(
            routes: [
                try .post("/auth/refresh", jsonBody: ["a": 1, "b": 2], response: .status(200)),
            ]
        )
        try await WireStubXCTestTestHelpers.withStartedServer(scenario: scenario) { wire in
            try await WireStubXCTestTestHelpers.perform(
                WireStubXCTestTestHelpers.makeRequest(
                    baseURL: wire.baseURL,
                    method: "POST",
                    path: "/auth/refresh",
                    body: requestBody
                )
            )

            try await wire.assertReceived(
                try .post("/auth/refresh", jsonBody: ["a": 1, "b": 2])
            )
        }
    }

    func testAssertNeverReceivedPasses() async throws {
        let scenario = StubScenario(routes: [.get("/feed", response: .status(200))])
        try await WireStubXCTestTestHelpers.withStartedServer(scenario: scenario) { wire in
            try await wire.assertNeverReceived(.post("/auth/login"))
        }
    }

    func testAssertNeverReceivedFails() async throws {
        let scenario = StubScenario(routes: [.post("/auth/login", response: .status(200))])
        try await WireStubXCTestTestHelpers.withStartedServer(scenario: scenario) { wire in
            try await WireStubXCTestTestHelpers.perform(.init(url: URL(string: "/auth/login", relativeTo: wire.baseURL)!).setting(method: "POST"))
            do {
                try await wire.assertNeverReceived(.post("/auth/login"))
                XCTFail("Expected failure")
            } catch {
                let message = WireStubXCTestTestHelpers.message(from: error)
                XCTAssertTrue(message.contains("Expected request never to occur"))
                XCTAssertTrue(message.contains("POST /auth/login"))
            }
        }
    }

    func testAssertReceivedSequencePasses() async throws {
        let scenario = StubScenario(routes: [
            .post("/auth/login", response: .status(200)),
            .get("/me", response: .status(200)),
            .get("/feed", response: .status(200))
        ], replayStrategy: .ordered)
        try await WireStubXCTestTestHelpers.withStartedServer(scenario: scenario) { wire in
            try await WireStubXCTestTestHelpers.perform(.init(url: URL(string: "/auth/login", relativeTo: wire.baseURL)!).setting(method: "POST"))
            try await WireStubXCTestTestHelpers.perform(WireStubXCTestTestHelpers.makeRequest(baseURL: wire.baseURL, path: "/me"))
            try await WireStubXCTestTestHelpers.perform(WireStubXCTestTestHelpers.makeRequest(baseURL: wire.baseURL, path: "/feed"))
            try await wire.assertReceivedSequence([.post("/auth/login"), .get("/me"), .get("/feed")])
        }
    }

    func testAssertReceivedSequenceFailsWithTimeline() async throws {
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
                XCTAssertTrue(message.contains("GET /feed"))
            }
        }
    }

    func testAssertNoUnmatchedRequestsPasses() async throws {
        let scenario = StubScenario(routes: [.get("/feed", response: .status(200))])
        try await WireStubXCTestTestHelpers.withStartedServer(scenario: scenario) { wire in
            try await WireStubXCTestTestHelpers.perform(WireStubXCTestTestHelpers.makeRequest(baseURL: wire.baseURL, path: "/feed"))
            try await wire.assertNoUnmatchedRequests()
        }
    }

    func testAssertNoUnmatchedRequestsFailsWithDiagnostics() async throws {
        let scenario = StubScenario(routes: [.get("/feed", response: .status(200))], mode: .strict)
        try await WireStubXCTestTestHelpers.withStartedServer(scenario: scenario) { wire in
            try await WireStubXCTestTestHelpers.perform(WireStubXCTestTestHelpers.makeRequest(baseURL: wire.baseURL, path: "/missing"))
            do {
                try await wire.assertNoUnmatchedRequests()
                XCTFail("Expected failure")
            } catch {
                let message = WireStubXCTestTestHelpers.message(from: error)
                XCTAssertTrue(message.contains("No matching WireStub route"))
                XCTAssertTrue(message.contains("/missing"))
            }
        }
    }
}
