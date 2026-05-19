import XCTest
import WireStubCore
import WireStubHAR
import WireStubServer
import WireStubXCTest

final class WireStubDemoUITests: XCTestCase {
    func testInlineScenarioDrivesLoginRefreshFlow() async throws {
        let wire = try LocalStubServer(scenario: inlineScenario())
        try await exerciseLoginFlow(using: wire)
    }

    func testHARScenarioDrivesLoginRefreshFlow() async throws {
        let archive = try HARLoader.load(from: fixtureURL("login_expire_refresh.har"))
        let scenario = try HARNormalizer.normalize(archive, name: "login_expire_refresh.har").scenario
        let wire = try LocalStubServer(scenario: scenario)
        try await exerciseLoginFlow(using: wire)
    }

    private func exerciseLoginFlow(using wire: LocalStubServer) async throws {
        try await wire.start()
        addTeardownBlock { [wire] in
            await wire.stop()
        }

        let app = XCUIApplication()
        try wire.configure(app, baseURLEnvironmentKeys: ["API_BASE_URL", "AUTH_BASE_URL"])
        app.launch()

        XCTAssertTrue(app.staticTexts["statusTitle"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["statusTitle"].label, "Logged Out")

        app.buttons["loginButton"].tap()

        let statusLabel = app.staticTexts["statusTitle"]
        XCTAssertTrue(statusLabel.waitForExistence(timeout: 5))

        let successPredicate = NSPredicate(format: "label == %@", "Feed Ready")
        expectation(for: successPredicate, evaluatedWith: statusLabel)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(app.staticTexts["statusSubtitle"].label.contains("Feed loaded"))

        try await wire.assertEventuallyReceivedSequence([
            .post("/auth/login"),
            .get("/me"),
            .get("/feed"),
            .post("/auth/refresh"),
            .get("/feed"),
        ])
        try await wire.assertEventuallyNoUnmatchedRequests()
        try await wire.assertEventuallyScenarioComplete()
    }

    func testStaleSessionBootstrapExpiresToLoggedOutState() async throws {
        let scenario = try StubScenario(
            name: "stale-session-expiry",
            routes: [
                .get(
                    "/me",
                    matching: .init(
                        id: "bootstrap-me",
                        headers: ["Authorization": "Bearer stale-token"]
                    ),
                    response: try .json(["name": "Blob"])
                ),
                .get(
                    "/notifications",
                    matching: .init(
                        id: "bootstrap-notifications",
                        headers: ["Authorization": "Bearer stale-token"]
                    ),
                    response: .status(401)
                ),
            ],
            mode: .strict,
            replayStrategy: .firstMatch
        )

        let wire = try LocalStubServer(scenario: scenario)
        try await wire.start()
        addTeardownBlock { [wire] in
            await wire.stop()
        }

        let app = XCUIApplication()
        app.launchEnvironment["DEMO_BOOTSTRAP_STATE"] = "authenticated-stale"
        try wire.configure(app, baseURLEnvironmentKeys: ["API_BASE_URL", "AUTH_BASE_URL"])
        app.launch()

        let statusLabel = app.staticTexts["statusTitle"]
        XCTAssertTrue(statusLabel.waitForExistence(timeout: 5))

        let expiredPredicate = NSPredicate(format: "label == %@", "Session Expired")
        expectation(for: expiredPredicate, evaluatedWith: statusLabel)
        waitForExpectations(timeout: 10)

        XCTAssertTrue(app.staticTexts["statusSubtitle"].label.contains("Please log in again"))

        try await wire.assertEventuallyReceived(
            .get("/me", headers: ["Authorization": "Bearer stale-token"])
        )
        try await wire.assertEventuallyReceived(
            .get("/notifications", headers: ["Authorization": "Bearer stale-token"])
        )
        try await wire.assertEventuallyReceived(
            .get("/me", headers: ["Authorization": "Bearer stale-token"]),
            count: 1
        )
        try await wire.assertEventuallyReceived(
            .get("/notifications", headers: ["Authorization": "Bearer stale-token"]),
            count: 1
        )
        try await wire.assertEventuallyNoUnmatchedRequests()
    }

    private func inlineScenario() throws -> StubScenario {
        StubScenario(
            name: "inline-login-expire-refresh",
            routes: [
                .post("/auth/login", matching: .init(id: "auth-login"), response: .status(200)),
                .get(
                    "/me",
                    matching: .init(
                        id: "load-me",
                        headers: ["Authorization": "Bearer fresh-token"]
                    ),
                    response: try .json(["name": "Blob"])
                ),
                .get(
                    "/feed",
                    matching: .init(
                        id: "feed-initial",
                        headers: ["Authorization": "Bearer fresh-token"]
                    ),
                    response: .status(401)
                ),
                .post(
                    "/auth/refresh",
                    matching: .init(
                        id: "auth-refresh",
                        headers: ["Authorization": "Bearer fresh-token"]
                    ),
                    response: .status(200)
                ),
                .get(
                    "/feed",
                    matching: .init(
                        id: "feed-retried",
                        headers: ["Authorization": "Bearer refreshed-token"]
                    ),
                    response: try .json(["message": "Feed loaded"])
                ),
            ],
            mode: .strict,
            replayStrategy: .ordered
        )
    }

    private func fixtureURL(_ name: String, file: StaticString = #filePath) -> URL {
        let fileURL = URL(fileURLWithPath: String(describing: file))
        return fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(name)
    }
}
