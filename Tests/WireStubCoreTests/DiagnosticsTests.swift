import XCTest
@testable import WireStubCore

final class DiagnosticsTests: XCTestCase {

    func testUnmatchedDiagnosticIncludesScenarioNameMethodPathAndClosestMismatch() async throws {
        let scenario = StubScenario(
            name: "login_flow",
            routes: [.post("/auth/login", response: .status(200))],
            replayStrategy: .firstMatch
        )
        let engine = StubEngine(scenario: scenario)

        let result = await engine.handle(RequestSnapshot(method: "GET", path: "/auth/login"))

        guard case .unmatched(let diagnostic) = result else {
            return XCTFail("Expected unmatched")
        }

        XCTAssertEqual(diagnostic.scenarioName, "login_flow")
        XCTAssertEqual(diagnostic.request.method, "GET")
        XCTAssertEqual(diagnostic.request.path, "/auth/login")

        let rendered = diagnostic.render()
        XCTAssertTrue(rendered.contains("login_flow"), "Diagnostic must include scenario name")
        XCTAssertTrue(rendered.contains("/auth/login"), "Diagnostic must include the requested path")
        XCTAssertFalse(diagnostic.closestCandidates.isEmpty, "Diagnostic must include closest candidates")
    }

    func testOrderedMismatchDiagnosticIncludesNextExpectedRequest() async throws {
        let firstRoute = StubRoute.post("/auth/login", response: .status(200))
        let scenario = StubScenario(
            routes: [firstRoute, .get("/me", response: .status(200))],
            replayStrategy: .ordered
        )
        let engine = StubEngine(scenario: scenario)

        // Send wrong request
        let result = await engine.handle(RequestSnapshot(method: "GET", path: "/wrong"))

        guard case .unmatched(let diagnostic) = result else {
            return XCTFail("Expected unmatched")
        }

        XCTAssertEqual(diagnostic.nextExpectedRouteID, firstRoute.id)
        XCTAssertTrue(diagnostic.render().contains(firstRoute.id))
    }

    func testDiagnosticIncludesRequestsReceivedSoFar() async throws {
        let scenario = StubScenario(
            routes: [
                .post("/auth/login", response: .status(200)),
                .get("/me", response: .status(200)),
            ],
            replayStrategy: .ordered
        )
        let engine = StubEngine(scenario: scenario)

        _ = await engine.handle(RequestSnapshot(method: "POST", path: "/auth/login"))
        let result = await engine.handle(RequestSnapshot(method: "GET", path: "/unexpected"))

        guard case .unmatched(let diagnostic) = result else {
            return XCTFail("Expected unmatched")
        }

        XCTAssertEqual(diagnostic.requestsReceivedSoFar.count, 1)
        XCTAssertEqual(diagnostic.requestsReceivedSoFar.first?.request.path, "/auth/login")
    }

    func testDiagnosticsRedactSensitiveHeaderValues() async throws {
        let scenario = StubScenario(
            routes: [.get("/secure", response: .status(200))],
            replayStrategy: .firstMatch
        )
        let engine = StubEngine(scenario: scenario)

        let request = RequestSnapshot(
            method: "GET",
            path: "/wrongpath",
            headers: [
                "Authorization": "Bearer supersecrettoken",
                "Cookie": "session=abc123",
                "X-Request-ID": "req-42",
            ]
        )
        let result = await engine.handle(request)

        guard case .unmatched(let diagnostic) = result else {
            return XCTFail("Expected unmatched")
        }

        let rendered = diagnostic.render()
        XCTAssertFalse(rendered.contains("supersecrettoken"), "Sensitive Authorization value must be redacted")
        XCTAssertFalse(rendered.contains("abc123"), "Sensitive Cookie value must be redacted")
        XCTAssertTrue(rendered.contains(Redactor.redactedPlaceholder), "Redaction placeholder must appear")
        // Non-sensitive headers must not be redacted
        XCTAssertTrue(rendered.contains("req-42"), "Non-sensitive header values must not be redacted")
    }

    func testSensitiveQueryRedactionRedactsAllDuplicateTokenKeys() async throws {
        let scenario = StubScenario(routes: [.get("/secure", response: .status(200))])
        let engine = StubEngine(scenario: scenario)

        let result = await engine.handle(
            RequestSnapshot(
                method: "GET",
                path: "/wrong",
                queryItems: [
                    QueryItem(name: "token", value: "secret-1"),
                    QueryItem(name: "token", value: "secret-2"),
                ]
            )
        )

        guard case .unmatched(let diagnostic) = result else {
            return XCTFail("Expected unmatched")
        }

        let rendered = diagnostic.render()
        XCTAssertTrue(rendered.contains("token=[REDACTED]"))
        XCTAssertFalse(rendered.contains("secret-1"))
        XCTAssertFalse(rendered.contains("secret-2"))
    }

    func testRenderedMismatchReasonsRedactSensitiveHeaderValues() {
        let reason = MismatchReason.headerMismatch(
            name: "Authorization",
            expected: "Bearer super-secret",
            received: "Bearer leaked"
        )

        let rendered = reason.renderedDescription(redacted: true)
        XCTAssertTrue(rendered.contains("[REDACTED]"))
        XCTAssertFalse(rendered.contains("super-secret"))
        XCTAssertFalse(rendered.contains("leaked"))
    }
}
