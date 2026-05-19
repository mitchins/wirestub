import XCTest
import WireStubCore
import WireStubURLProtocol

final class URLProtocolReplayTests: XCTestCase {
    func testURLProtocolAdapterReturnsStubbedResponse() async throws {
        let response = StubResponse.text("stubbed", status: 202, headers: ["X-Mode": "urlprotocol"])
        let scenario = StubScenario(routes: [.get("/items", response: response)])

        try await URLProtocolTestHelpers.withInstalledSession(scenario: scenario) { session, _ in
            let request = URLProtocolTestHelpers.makeRequest(path: "/items")
            let (http, data) = try await URLProtocolTestHelpers.perform(request, session: session)

            XCTAssertEqual(http.statusCode, 202)
            XCTAssertEqual(http.value(forHTTPHeaderField: "X-Mode"), "urlprotocol")
            XCTAssertEqual(String(decoding: data, as: UTF8.self), "stubbed")
        }
    }

    func testURLProtocolAdapterCapturesRequestBody() async throws {
        let expectedBody = #"{"a":1,"b":2}"#.data(using: .utf8)!
        let policy = MatchingPolicy(components: [.method, .path, .canonicalJSONBodyHash])
        let route = StubRoute(
            matcher: RouteMatcher(method: "POST", path: "/login", body: expectedBody, policy: policy),
            responseProvider: .staticResponse(.status(201))
        )
        let scenario = StubScenario(routes: [route])

        try await URLProtocolTestHelpers.withInstalledSession(scenario: scenario) { session, _ in
            let requestBody = #"{"b":2,"a":1}"#.data(using: .utf8)!
            let request = URLProtocolTestHelpers.makeRequest(
                method: "POST",
                path: "/login",
                headers: ["Content-Type": "application/json"],
                body: requestBody
            )
            let (http, _) = try await URLProtocolTestHelpers.perform(request, session: session)
            XCTAssertEqual(http.statusCode, 201)
        }
    }

    func testURLProtocolAdapterRecordsJournalEntry() async throws {
        let route = StubRoute.get("/feed", response: .status(200))
        let scenario = StubScenario(routes: [route])

        try await URLProtocolTestHelpers.withInstalledSession(scenario: scenario) { session, installation in
            let request = URLProtocolTestHelpers.makeRequest(path: "/feed")
            _ = try await URLProtocolTestHelpers.perform(request, session: session)

            let journal = await installation.engine.currentJournal()
            XCTAssertEqual(journal.entries.count, 1)
            XCTAssertEqual(journal.entries[0].request.method, "GET")
            XCTAssertEqual(journal.entries[0].request.path, "/feed")
            XCTAssertEqual(URLProtocolTestHelpers.matchedOutcome(journal.entries[0])?.routeID, route.id)
        }
    }

    func testURLProtocolAdapterReturnsUnmatchedDiagnostic() async throws {
        let scenario = StubScenario(routes: [.get("/known", response: .status(200))], mode: .strict)

        try await URLProtocolTestHelpers.withInstalledSession(scenario: scenario) { session, _ in
            let request = URLProtocolTestHelpers.makeRequest(
                path: "/unknown",
                headers: ["Authorization": "Bearer secret-token"]
            )
            let (http, data) = try await URLProtocolTestHelpers.perform(request, session: session)
            let body = String(decoding: data, as: UTF8.self)

            XCTAssertEqual(http.statusCode, 501)
            XCTAssertTrue(body.contains("No matching WireStub route"))
            XCTAssertTrue(body.contains("/unknown"))
            XCTAssertTrue(body.contains("[REDACTED]"))
            XCTAssertFalse(body.contains("secret-token"))
        }
    }

    func testURLProtocolUnmatchedDiagnosticBodyRedactsSensitiveValues() async throws {
        let scenario = StubScenario(routes: [.get("/known", response: .status(200))], mode: .strict)

        try await URLProtocolTestHelpers.withInstalledSession(scenario: scenario) { session, _ in
            let request = URLProtocolTestHelpers.makeRequest(
                path: "/unknown",
                queryItems: [
                    URLQueryItem(name: "token", value: "secret-1"),
                    URLQueryItem(name: "token", value: "secret-2"),
                ],
                headers: ["Authorization": "Bearer secret-token", "Cookie": "session=abc123"]
            )
            let (_, data) = try await URLProtocolTestHelpers.perform(request, session: session)
            let body = String(decoding: data, as: UTF8.self)
            XCTAssertFalse(body.contains("secret-token"))
            XCTAssertFalse(body.contains("abc123"))
            XCTAssertFalse(body.contains("secret-1"))
            XCTAssertFalse(body.contains("secret-2"))
            XCTAssertTrue(body.contains("token=[REDACTED]"))
        }
    }

    func testURLProtocolAdapterDoesNotOwnMatchingLogic() async throws {
        let policy = MatchingPolicy(components: [.method, .path, .querySubset])
        let route = StubRoute(
            matcher: RouteMatcher(
                method: "GET",
                path: "/search",
                queryItems: [QueryItem(name: "q", value: "wirestub")],
                policy: policy
            ),
            responseProvider: .staticResponse(.status(204))
        )
        let scenario = StubScenario(routes: [route])

        try await URLProtocolTestHelpers.withInstalledSession(scenario: scenario) { session, _ in
            let request = URLProtocolTestHelpers.makeRequest(
                path: "/search",
                queryItems: [
                    URLQueryItem(name: "q", value: "wirestub"),
                    URLQueryItem(name: "page", value: "1"),
                ]
            )
            let (http, _) = try await URLProtocolTestHelpers.perform(request, session: session)
            XCTAssertEqual(http.statusCode, 204)
        }
    }

    func testURLProtocolHonorsStubResponseDelay() async throws {
        let scenario = StubScenario(routes: [.get("/delay", response: .text("slow", delay: .milliseconds(80)))])

        try await URLProtocolTestHelpers.withInstalledSession(scenario: scenario) { session, _ in
            let request = URLProtocolTestHelpers.makeRequest(path: "/delay")
            let start = ContinuousClock.now
            _ = try await URLProtocolTestHelpers.perform(request, session: session)
            let elapsed = ContinuousClock.now - start
            XCTAssertGreaterThanOrEqual(elapsed, .milliseconds(80))
        }
    }
}
