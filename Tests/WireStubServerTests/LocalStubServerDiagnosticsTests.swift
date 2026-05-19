import XCTest
@testable import WireStubServer
import WireStubCore

final class LocalStubServerDiagnosticsTests: XCTestCase {
    func testStrictUnmatchedHTTPResponseContainsDiagnosticBody() async throws {
        let scenario = StubScenario(routes: [.get("/known", response: .status(200))], mode: .strict)

        try await ServerTestHelpers.withStartedServer(scenario: scenario) { server in
            let request = ServerTestHelpers.makeRequest(baseURL: server.baseURL, path: "/unknown")
            let (http, data) = try await ServerTestHelpers.perform(request)
            XCTAssertEqual(http.statusCode, 501)
            XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("No matching WireStub route"))
        }
    }

    func testDiagnosticBodyMentionsClosestCandidate() async throws {
        let scenario = StubScenario(routes: [.post("/auth/refresh", response: .status(200))], mode: .strict)

        try await ServerTestHelpers.withStartedServer(scenario: scenario) { server in
            let request = ServerTestHelpers.makeRequest(baseURL: server.baseURL, method: "POST", path: "/auth/refesh")
            let (_, data) = try await ServerTestHelpers.perform(request)
            let body = String(decoding: data, as: UTF8.self)
            XCTAssertTrue(body.contains("/auth/refresh"))
            XCTAssertTrue(body.contains("Closest candidates"))
        }
    }

    func testDiagnosticBodyMentionsExpectedNextRouteInOrderedMode() async throws {
        let first = StubRoute.post("/auth/login", response: .status(200))
        let second = StubRoute.post("/auth/refresh", response: .status(200))
        let scenario = StubScenario(routes: [first, second], mode: .strict, replayStrategy: .ordered)

        try await ServerTestHelpers.withStartedServer(scenario: scenario) { server in
            _ = try await ServerTestHelpers.perform(ServerTestHelpers.makeRequest(baseURL: server.baseURL, method: "POST", path: "/auth/login"))
            let request = ServerTestHelpers.makeRequest(baseURL: server.baseURL, method: "POST", path: "/wrong")
            let (_, data) = try await ServerTestHelpers.perform(request)
            let body = String(decoding: data, as: UTF8.self)
            XCTAssertTrue(body.contains("Expected next route"))
            XCTAssertTrue(body.contains(second.id))
        }
    }

    func testDiagnosticBodyRedactsSensitiveHeaders() async throws {
        let scenario = StubScenario(routes: [.get("/known", response: .status(200))], mode: .strict)

        try await ServerTestHelpers.withStartedServer(scenario: scenario) { server in
            let request = ServerTestHelpers.makeRequest(
                baseURL: server.baseURL,
                path: "/unknown",
                headers: [
                    "Authorization": "Bearer super-secret-token",
                    "Cookie": "session=abc123",
                    "X-Request-ID": "req-123",
                ]
            )
            let (_, data) = try await ServerTestHelpers.perform(request)
            let body = String(decoding: data, as: UTF8.self)
            XCTAssertFalse(body.contains("super-secret-token"))
            XCTAssertFalse(body.contains("abc123"))
            XCTAssertTrue(body.contains(Redactor.redactedPlaceholder))
            XCTAssertTrue(body.contains("req-123"))
        }
    }

    func testServerUnmatchedDiagnosticBodyRedactsAuthorizationCookieAndTokenQuery() async throws {
        let scenario = StubScenario(routes: [.get("/known", response: .status(200))], mode: .strict)

        try await ServerTestHelpers.withStartedServer(scenario: scenario) { server in
            let request = ServerTestHelpers.makeRequest(
                baseURL: server.baseURL,
                path: "/unknown",
                queryItems: [
                    URLQueryItem(name: "token", value: "secret-1"),
                    URLQueryItem(name: "token", value: "secret-2"),
                ],
                headers: [
                    "Authorization": "Bearer super-secret-token",
                    "Cookie": "session=abc123",
                ]
            )
            let (_, data) = try await ServerTestHelpers.perform(request)
            let body = String(decoding: data, as: UTF8.self)
            XCTAssertFalse(body.contains("super-secret-token"))
            XCTAssertFalse(body.contains("abc123"))
            XCTAssertFalse(body.contains("secret-1"))
            XCTAssertFalse(body.contains("secret-2"))
            XCTAssertTrue(body.contains("token=[REDACTED]"))
        }
    }
}
