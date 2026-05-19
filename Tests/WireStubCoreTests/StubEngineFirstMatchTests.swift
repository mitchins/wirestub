import XCTest
@testable import WireStubCore

final class StubEngineFirstMatchTests: XCTestCase {

    func testFirstMatchReturnsStaticJSONResponseForMatchingMethodAndPath() async throws {
        let response = StubResponse.text("hello", status: 200)
        let scenario = StubScenario(
            routes: [.get("/hello", response: response)],
            replayStrategy: .firstMatch
        )
        let engine = StubEngine(scenario: scenario)

        let result = await engine.handle(RequestSnapshot(method: "GET", path: "/hello"))

        guard case .matched(let stubResponse, _) = result else {
            return XCTFail("Expected matched result")
        }
        XCTAssertEqual(stubResponse.status, 200)
        XCTAssertEqual(stubResponse.body, "hello".data(using: .utf8))
    }

    func testDefaultUIReplayMatchingIgnoresSchemeHostAndPort() async throws {
        let response = StubResponse.status(200)
        let scenario = StubScenario(
            routes: [.get("/api/feed", response: response)],
            replayStrategy: .firstMatch
        )
        let engine = StubEngine(scenario: scenario)

        // Simulate a request that came from https://api.example.com:443/api/feed
        let request = RequestSnapshot(
            method: "GET",
            path: "/api/feed",
            target: RequestTarget(scheme: "https", host: "api.example.com", port: 443)
        )
        let result = await engine.handle(request)

        guard case .matched = result else {
            return XCTFail("Expected match — default policy must ignore scheme/host/port")
        }
    }

    func testUnmatchedRequestInStrictModeReturnsDiagnosticAndRecordsJournal() async throws {
        let scenario = StubScenario(
            routes: [.get("/expected", response: .status(200))],
            mode: .strict,
            replayStrategy: .firstMatch
        )
        let engine = StubEngine(scenario: scenario)

        let result = await engine.handle(RequestSnapshot(method: "GET", path: "/unexpected"))

        guard case .unmatched(let diagnostic) = result else {
            return XCTFail("Expected unmatched result in strict mode")
        }
        XCTAssertEqual(diagnostic.request.path, "/unexpected")
        XCTAssertFalse(diagnostic.render().isEmpty)

        let journal = await engine.currentJournal()
        XCTAssertEqual(journal.unmatchedEntries.count, 1)
    }
}
