import XCTest
@testable import WireStubServer
import WireStubCore

final class LocalStubServerReplayTests: XCTestCase {
    func testServerUsesCoreFirstMatchReplay() async throws {
        let scenario = StubScenario(routes: [.get("/items", response: .status(200))], replayStrategy: .firstMatch)

        try await ServerTestHelpers.withStartedServer(scenario: scenario) { server in
            let request = ServerTestHelpers.makeRequest(baseURL: server.baseURL, path: "/items")
            let (http, _) = try await ServerTestHelpers.perform(request)
            XCTAssertEqual(http.statusCode, 200)
        }
    }

    func testServerUsesCoreOrderedReplay() async throws {
        let scenario = StubScenario(
            routes: [
                .post("/auth/login", response: .status(200)),
                .get("/feed", response: .status(401)),
                .post("/auth/refresh", response: .status(200)),
                .get("/feed", response: .status(200)),
            ],
            replayStrategy: .ordered
        )

        try await ServerTestHelpers.withStartedServer(scenario: scenario) { server in
            let r1 = try await ServerTestHelpers.perform(ServerTestHelpers.makeRequest(baseURL: server.baseURL, method: "POST", path: "/auth/login"))
            let r2 = try await ServerTestHelpers.perform(ServerTestHelpers.makeRequest(baseURL: server.baseURL, path: "/feed"))
            let r3 = try await ServerTestHelpers.perform(ServerTestHelpers.makeRequest(baseURL: server.baseURL, method: "POST", path: "/auth/refresh"))
            let r4 = try await ServerTestHelpers.perform(ServerTestHelpers.makeRequest(baseURL: server.baseURL, path: "/feed"))
            XCTAssertEqual(r1.0.statusCode, 200)
            XCTAssertEqual(r2.0.statusCode, 401)
            XCTAssertEqual(r3.0.statusCode, 200)
            XCTAssertEqual(r4.0.statusCode, 200)
        }
    }

    func testServerSupportsRepeatedSamePathDifferentResponses() async throws {
        let scenario = StubScenario(
            routes: [
                .get("/feed", response: .status(200)),
                .get("/feed", response: .status(401)),
                .get("/feed", response: .status(200)),
            ],
            replayStrategy: .ordered
        )

        try await ServerTestHelpers.withStartedServer(scenario: scenario) { server in
            let one = try await ServerTestHelpers.perform(ServerTestHelpers.makeRequest(baseURL: server.baseURL, path: "/feed"))
            let two = try await ServerTestHelpers.perform(ServerTestHelpers.makeRequest(baseURL: server.baseURL, path: "/feed"))
            let three = try await ServerTestHelpers.perform(ServerTestHelpers.makeRequest(baseURL: server.baseURL, path: "/feed"))
            XCTAssertEqual([one.0.statusCode, two.0.statusCode, three.0.statusCode], [200, 401, 200])
        }
    }

    func testServerSupportsSequenceResponses() async throws {
        let route = StubRoute.sequence(method: "GET", path: "/seq", responses: [.status(200), .status(201), .status(202)])
        let scenario = StubScenario(routes: [route], replayStrategy: .firstMatch)

        try await ServerTestHelpers.withStartedServer(scenario: scenario) { server in
            let one = try await ServerTestHelpers.perform(ServerTestHelpers.makeRequest(baseURL: server.baseURL, path: "/seq"))
            let two = try await ServerTestHelpers.perform(ServerTestHelpers.makeRequest(baseURL: server.baseURL, path: "/seq"))
            let three = try await ServerTestHelpers.perform(ServerTestHelpers.makeRequest(baseURL: server.baseURL, path: "/seq"))
            XCTAssertEqual(one.0.statusCode, 200)
            XCTAssertEqual(two.0.statusCode, 201)
            XCTAssertEqual(three.0.statusCode, 202)
        }
    }

    func testServerUnmatchedRequestIsRecordedInJournal() async throws {
        let scenario = StubScenario(routes: [.get("/known", response: .status(200))], mode: .strict)

        try await ServerTestHelpers.withStartedServer(scenario: scenario) { server in
            _ = try await ServerTestHelpers.perform(ServerTestHelpers.makeRequest(baseURL: server.baseURL, path: "/unknown"))
            let journal = await server.journal()
            XCTAssertEqual(journal.unmatchedEntries.count, 1)
        }
    }

    func testServerResponseMatchesCoreEngineForEquivalentSnapshot() async throws {
        let response = StubResponse.text("hello world", status: 202, headers: ["X-Test": "yes"])
        let scenario = StubScenario(routes: [.get("/parity", response: response)])
        let engine = StubEngine(scenario: scenario)

        let snapshot = RequestSnapshot(method: "GET", path: "/parity")
        let expected = await engine.handle(snapshot)

        try await ServerTestHelpers.withStartedServer(scenario: scenario) { server in
            let request = ServerTestHelpers.makeRequest(baseURL: server.baseURL, path: "/parity")
            let (http, data) = try await ServerTestHelpers.perform(request)
            guard case .matched(let stubResponse, _) = expected else {
                return XCTFail("Expected core match")
            }
            XCTAssertEqual(http.statusCode, stubResponse.status)
            XCTAssertEqual(http.value(forHTTPHeaderField: "X-Test"), "yes")
            XCTAssertEqual(data, stubResponse.body)
        }
    }
}
