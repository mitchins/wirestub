import XCTest
import WireStubCore
import WireStubServer
import WireStubURLProtocol

final class URLProtocolSharedEngineParityTests: XCTestCase {
    func testURLProtocolAndServerProduceSameResponseForSameScenario() async throws {
        let stub = StubResponse.text("hello parity", status: 203, headers: ["X-Parity": "yes"])
        let scenario = StubScenario(routes: [.get("/parity", response: stub)])

        try await URLProtocolTestHelpers.withInstalledSession(scenario: scenario) { session, _ in
            try await URLProtocolTestHelpers.withStartedServer(scenario: scenario) { server in
                let urlProtocolRequest = URLProtocolTestHelpers.makeRequest(path: "/parity")
                let serverRequest = URLProtocolTestHelpers.makeRequest(baseURL: server.baseURL, path: "/parity")

                let urlProtocolResult = try await URLProtocolTestHelpers.perform(urlProtocolRequest, session: session)
                let serverResult = try await URLProtocolTestHelpers.performServerRequest(serverRequest)

                XCTAssertEqual(urlProtocolResult.0.statusCode, serverResult.0.statusCode)
                XCTAssertEqual(urlProtocolResult.0.value(forHTTPHeaderField: "X-Parity"), serverResult.0.value(forHTTPHeaderField: "X-Parity"))
                XCTAssertEqual(urlProtocolResult.1, serverResult.1)
            }
        }
    }

    func testURLProtocolAndServerProduceEquivalentJournalEntries() async throws {
        let body = #"{"name":"wirestub"}"#.data(using: .utf8)!
        let policy = MatchingPolicy(components: [.method, .path, .canonicalJSONBodyHash])
        let route = StubRoute(
            matcher: RouteMatcher(method: "POST", path: "/submit", body: body, policy: policy),
            responseProvider: .staticResponse(.status(200))
        )
        let scenario = StubScenario(routes: [route])

        try await URLProtocolTestHelpers.withInstalledSession(scenario: scenario) { session, installation in
            try await URLProtocolTestHelpers.withStartedServer(scenario: scenario) { server in
                let payload = #"{"name":"wirestub"}"#.data(using: .utf8)!
                let urlProtocolRequest = URLProtocolTestHelpers.makeRequest(method: "POST", path: "/submit", body: payload)
                let serverRequest = URLProtocolTestHelpers.makeRequest(baseURL: server.baseURL, method: "POST", path: "/submit", body: payload)

                _ = try await URLProtocolTestHelpers.perform(urlProtocolRequest, session: session)
                _ = try await URLProtocolTestHelpers.performServerRequest(serverRequest)

                let urlProtocolJournal = await installation.engine.currentJournal()
                let serverJournal = await server.journal()
                XCTAssertEqual(urlProtocolJournal.entries.count, 1)
                XCTAssertEqual(serverJournal.entries.count, 1)

                let urlEntry = urlProtocolJournal.entries[0]
                let serverEntry = serverJournal.entries[0]

                XCTAssertEqual(urlEntry.request.method, serverEntry.request.method)
                XCTAssertEqual(urlEntry.request.path, serverEntry.request.path)
                XCTAssertEqual(urlEntry.request.queryItems, serverEntry.request.queryItems)
                XCTAssertEqual(urlEntry.request.body, serverEntry.request.body)
                XCTAssertEqual(URLProtocolTestHelpers.matchedOutcome(urlEntry)?.routeID, URLProtocolTestHelpers.matchedOutcome(serverEntry)?.routeID)
                XCTAssertEqual(URLProtocolTestHelpers.matchedOutcome(urlEntry)?.status, URLProtocolTestHelpers.matchedOutcome(serverEntry)?.status)
            }
        }
    }

    func testURLProtocolAndServerProduceEquivalentUnmatchedDiagnostics() async throws {
        let scenario = StubScenario(routes: [.get("/known", response: .status(200))], mode: .strict)

        try await URLProtocolTestHelpers.withInstalledSession(scenario: scenario) { session, _ in
            try await URLProtocolTestHelpers.withStartedServer(scenario: scenario) { server in
                let headers = ["Authorization": "Bearer secret-token"]
                let queryItems = [URLQueryItem(name: "token", value: "secret-value")]
                let urlProtocolRequest = URLProtocolTestHelpers.makeRequest(
                    path: "/wrong",
                    queryItems: queryItems,
                    headers: headers
                )
                let serverRequest = URLProtocolTestHelpers.makeRequest(
                    baseURL: server.baseURL,
                    path: "/wrong",
                    queryItems: queryItems,
                    headers: headers
                )

                let urlProtocolResult = try await URLProtocolTestHelpers.perform(urlProtocolRequest, session: session)
                let serverResult = try await URLProtocolTestHelpers.performServerRequest(serverRequest)
                let urlProtocolBody = String(decoding: urlProtocolResult.1, as: UTF8.self)
                let serverBody = String(decoding: serverResult.1, as: UTF8.self)

                XCTAssertEqual(urlProtocolResult.0.statusCode, serverResult.0.statusCode)
                XCTAssertTrue(urlProtocolBody.contains("No matching WireStub route for GET /wrong"))
                XCTAssertTrue(serverBody.contains("No matching WireStub route for GET /wrong"))
                XCTAssertTrue(urlProtocolBody.contains("Route "))
                XCTAssertTrue(serverBody.contains("Route "))
                XCTAssertTrue(urlProtocolBody.contains("path mismatch: expected /known, got /wrong"))
                XCTAssertTrue(serverBody.contains("path mismatch: expected /known, got /wrong"))
                XCTAssertTrue(urlProtocolBody.contains("token=[REDACTED]"))
                XCTAssertTrue(serverBody.contains("token=[REDACTED]"))
                XCTAssertFalse(urlProtocolBody.contains("secret-token"))
                XCTAssertFalse(serverBody.contains("secret-token"))
            }
        }
    }

    func testCoreServerURLProtocolDelayParity() async throws {
        let response = StubResponse.text("slow", delay: .milliseconds(80))
        let scenario = StubScenario(routes: [.get("/delay", response: response)])

        try await URLProtocolTestHelpers.withInstalledSession(scenario: scenario) { session, _ in
            try await URLProtocolTestHelpers.withStartedServer(scenario: scenario) { server in
                let urlProtocolRequest = URLProtocolTestHelpers.makeRequest(path: "/delay")
                let serverRequest = URLProtocolTestHelpers.makeRequest(baseURL: server.baseURL, path: "/delay")

                let urlProtocolStart = ContinuousClock.now
                _ = try await URLProtocolTestHelpers.perform(urlProtocolRequest, session: session)
                let urlProtocolElapsed = ContinuousClock.now - urlProtocolStart

                let serverStart = ContinuousClock.now
                _ = try await URLProtocolTestHelpers.performServerRequest(serverRequest)
                let serverElapsed = ContinuousClock.now - serverStart

                XCTAssertGreaterThanOrEqual(urlProtocolElapsed, .milliseconds(80))
                XCTAssertGreaterThanOrEqual(serverElapsed, .milliseconds(80))
            }
        }
    }
}
