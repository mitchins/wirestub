import XCTest
@testable import WireStubServer
import WireStubCore

final class LocalStubServerHTTPTests: XCTestCase {
    func testGETRequestReturnsStubbedText() async throws {
        let scenario = StubScenario(routes: [.get("/hello", response: .text("hello"))])

        try await ServerTestHelpers.withStartedServer(scenario: scenario) { server in
            let request = ServerTestHelpers.makeRequest(baseURL: server.baseURL, path: "/hello")
            let (response, data) = try await ServerTestHelpers.perform(request)
            XCTAssertEqual(response.statusCode, 200)
            XCTAssertEqual(String(data: data, encoding: .utf8), "hello")
        }
    }

    func testGETRequestReturnsStubbedJSON() async throws {
        let json = try StubResponse.json(["status": "ok"] as [String: String])
        let scenario = StubScenario(routes: [.get("/json", response: json)])

        try await ServerTestHelpers.withStartedServer(scenario: scenario) { server in
            let request = ServerTestHelpers.makeRequest(baseURL: server.baseURL, path: "/json")
            let (response, data) = try await ServerTestHelpers.perform(request)
            XCTAssertEqual(response.statusCode, 200)
            XCTAssertEqual(response.value(forHTTPHeaderField: "Content-Type"), "application/json")
            let payload = try JSONSerialization.jsonObject(with: data) as? [String: String]
            XCTAssertEqual(payload?["status"], "ok")
        }
    }

    func testPOSTRequestBodyIsReadAndMatched() async throws {
        let body = Data("{\"action\":\"login\"}".utf8)
        let route = StubRoute(
            matcher: RouteMatcher(
                method: "POST",
                path: "/auth/login",
                body: body,
                policy: MatchingPolicy(components: [.method, .path, .bodyHash])
            ),
            responseProvider: .staticResponse(.status(201))
        )
        let scenario = StubScenario(routes: [route])

        try await ServerTestHelpers.withStartedServer(scenario: scenario) { server in
            let request = ServerTestHelpers.makeRequest(
                baseURL: server.baseURL,
                method: "POST",
                path: "/auth/login",
                headers: ["Content-Type": "application/json"],
                body: body
            )
            let (response, _) = try await ServerTestHelpers.perform(request)
            XCTAssertEqual(response.statusCode, 201)
        }
    }

    func testRequestHeadersAreCaptured() async throws {
        let scenario = StubScenario(routes: [.get("/headers", response: .status(200))])

        try await ServerTestHelpers.withStartedServer(scenario: scenario) { server in
            let request = ServerTestHelpers.makeRequest(
                baseURL: server.baseURL,
                path: "/headers",
                headers: ["X-Test-Header": "present"]
            )
            _ = try await ServerTestHelpers.perform(request)
            let journal = await server.journal()
            let value = ServerTestHelpers.headerValue("X-Test-Header", in: try XCTUnwrap(journal.entries.first?.request.headers))
            XCTAssertEqual(value, "present")
        }
    }

    func testQueryItemsAreCaptured() async throws {
        let scenario = StubScenario(routes: [.get("/search", response: .status(200))])

        try await ServerTestHelpers.withStartedServer(scenario: scenario) { server in
            let request = ServerTestHelpers.makeRequest(
                baseURL: server.baseURL,
                path: "/search",
                queryItems: [URLQueryItem(name: "q", value: "swift")]
            )
            _ = try await ServerTestHelpers.perform(request)
            let journal = await server.journal()
            let value = ServerTestHelpers.queryValue("q", in: try XCTUnwrap(journal.entries.first?.request.queryItems))
            XCTAssertEqual(value, "swift")
        }
    }

    func testResponseHeadersAreWritten() async throws {
        let response = StubResponse(status: 202, headers: ["X-Reply": "yes"], body: Data("ok".utf8))
        let scenario = StubScenario(routes: [.get("/headers", response: response)])

        try await ServerTestHelpers.withStartedServer(scenario: scenario) { server in
            let request = ServerTestHelpers.makeRequest(baseURL: server.baseURL, path: "/headers")
            let (http, _) = try await ServerTestHelpers.perform(request)
            XCTAssertEqual(http.value(forHTTPHeaderField: "X-Reply"), "yes")
        }
    }

    func testResponseStatusIsWritten() async throws {
        let scenario = StubScenario(routes: [.get("/status", response: .status(204))])

        try await ServerTestHelpers.withStartedServer(scenario: scenario) { server in
            let request = ServerTestHelpers.makeRequest(baseURL: server.baseURL, path: "/status")
            let (http, data) = try await ServerTestHelpers.perform(request)
            XCTAssertEqual(http.statusCode, 204)
            XCTAssertEqual(data.count, 0)
        }
    }

    func testUnknownRequestReturnsDiagnosticStatusInStrictMode() async throws {
        let scenario = StubScenario(
            routes: [.get("/known", response: .status(200))],
            mode: .strict
        )

        try await ServerTestHelpers.withStartedServer(scenario: scenario) { server in
            let request = ServerTestHelpers.makeRequest(baseURL: server.baseURL, path: "/unknown")
            let (http, data) = try await ServerTestHelpers.perform(request)
            XCTAssertEqual(http.statusCode, 501)
            XCTAssertTrue(String(data: data, encoding: .utf8)?.contains("No matching WireStub route") == true)
        }
    }

    func testLargeEnoughBodyIsHandled() async throws {
        let body = Data(repeating: 65, count: 128 * 1024)
        let route = StubRoute(
            matcher: RouteMatcher(
                method: "POST",
                path: "/upload",
                body: body,
                policy: MatchingPolicy(components: [.method, .path, .bodyHash])
            ),
            responseProvider: .staticResponse(.status(202))
        )
        let scenario = StubScenario(routes: [route])

        try await ServerTestHelpers.withStartedServer(scenario: scenario) { server in
            let request = ServerTestHelpers.makeRequest(baseURL: server.baseURL, method: "POST", path: "/upload", body: body)
            let (http, _) = try await ServerTestHelpers.perform(request)
            XCTAssertEqual(http.statusCode, 202)
        }
    }

    func testServerRequestAdapterDoesNotCrashOnDuplicateHeaders() async throws {
        let scenario = StubScenario(routes: [.get("/headers", response: .status(200))])

        try await ServerTestHelpers.withStartedServer(scenario: scenario) { server in
            var request = ServerTestHelpers.makeRequest(baseURL: server.baseURL, path: "/headers")
            request.addValue("Bearer one", forHTTPHeaderField: "Authorization")
            request.addValue("Bearer two", forHTTPHeaderField: "Authorization")
            _ = try await ServerTestHelpers.perform(request)

            let journal = await server.journal()
            let headers = try XCTUnwrap(journal.entries.first?.request.headers)
            let authorization = try XCTUnwrap(ServerTestHelpers.headerValue("Authorization", in: headers))
            XCTAssertTrue(authorization.contains("Bearer one"))
            XCTAssertTrue(authorization.contains("Bearer two"))
        }
    }

    func testRedactionAppliesToDuplicateSensitiveHeaders() async throws {
        let scenario = StubScenario(routes: [.get("/known", response: .status(200))], mode: .strict)

        try await ServerTestHelpers.withStartedServer(scenario: scenario) { server in
            var request = ServerTestHelpers.makeRequest(baseURL: server.baseURL, path: "/unknown")
            request.addValue("Bearer one", forHTTPHeaderField: "Authorization")
            request.addValue("Bearer two", forHTTPHeaderField: "Authorization")
            let (_, data) = try await ServerTestHelpers.perform(request)
            let body = String(decoding: data, as: UTF8.self)
            XCTAssertFalse(body.contains("Bearer one"))
            XCTAssertFalse(body.contains("Bearer two"))
            XCTAssertTrue(body.contains("[REDACTED]"))
        }
    }

    func testServerHonorsStubResponseDelay() async throws {
        let scenario = StubScenario(routes: [.get("/delayed", response: .text("slow", delay: .milliseconds(80)))])

        try await ServerTestHelpers.withStartedServer(scenario: scenario) { server in
            let request = ServerTestHelpers.makeRequest(baseURL: server.baseURL, path: "/delayed")
            let start = ContinuousClock.now
            _ = try await ServerTestHelpers.perform(request)
            let elapsed = ContinuousClock.now - start
            XCTAssertGreaterThanOrEqual(elapsed, .milliseconds(80))
        }
    }
}
