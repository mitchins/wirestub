import XCTest
@testable import WireStubXCTest
import WireStubServer
import WireStubCore

final class XCUIApplicationConfigurationTests: XCTestCase {
    func testConfigureAppSetsBaseURLEnvironmentVariable() async throws {
        let app = FakeLaunchConfigurable()
        let scenario = StubScenario(routes: [.get("/ping", response: .status(200))])

        try await WireStubXCTestTestHelpers.withStartedServer(scenario: scenario) { wire in
            try wire.configure(app, baseURLEnvironmentKey: "API_BASE_URL")
            XCTAssertEqual(app.launchEnvironment["API_BASE_URL"], wire.baseURL.absoluteString)
        }
    }

    func testConfigureAppDoesNotSetScenarioInternalsByDefault() async throws {
        let app = FakeLaunchConfigurable()
        let scenario = StubScenario(name: "login_flow", routes: [.get("/ping", response: .status(200))], mode: .strict, replayStrategy: .ordered)

        try await WireStubXCTestTestHelpers.withStartedServer(scenario: scenario) { wire in
            try wire.configure(app, baseURLEnvironmentKey: "API_BASE_URL")
            XCTAssertEqual(app.launchEnvironment.keys.sorted(), ["API_BASE_URL"])
            XCTAssertNil(app.launchEnvironment["WIRESTUB_SCENARIO"])
            XCTAssertNil(app.launchEnvironment["WIRESTUB_MODE"])
            XCTAssertNil(app.launchEnvironment["HAR_FILENAME"])
        }
    }

    func testConfigureAppAllowsCustomEnvironmentKey() async throws {
        let app = FakeLaunchConfigurable()
        let scenario = StubScenario(routes: [.get("/ping", response: .status(200))])

        try await WireStubXCTestTestHelpers.withStartedServer(scenario: scenario) { wire in
            try wire.configure(app, baseURLEnvironmentKey: "AUTH_BASE_URL")
            XCTAssertEqual(app.launchEnvironment["AUTH_BASE_URL"], wire.baseURL.absoluteString)
            XCTAssertNil(app.launchEnvironment["API_BASE_URL"])
        }
    }

    func testConfigureAppCanSetMultipleBaseURLs() async throws {
        let app = FakeLaunchConfigurable()
        let scenario = StubScenario(routes: [.get("/ping", response: .status(200))])

        try await WireStubXCTestTestHelpers.withStartedServer(scenario: scenario) { wire in
            try wire.configure(app, baseURLEnvironmentKeys: ["AUTH_BASE_URL", "API_BASE_URL"])
            XCTAssertEqual(app.launchEnvironment["AUTH_BASE_URL"], wire.baseURL.absoluteString)
            XCTAssertEqual(app.launchEnvironment["API_BASE_URL"], wire.baseURL.absoluteString)
        }
    }

    func testConfigureAppBeforeServerStartThrowsUsefulError() throws {
        let app = FakeLaunchConfigurable()
        let wire = try LocalStubServer(scenario: StubScenario(routes: [.get("/ping", response: .status(200))]))

        XCTAssertThrowsError(try wire.configure(app, baseURLEnvironmentKey: "API_BASE_URL")) { error in
            XCTAssertEqual(error as? WireStubXCTestError, .serverNotStarted)
        }
    }

    func testConfigureAppAfterServerStartInjectsRealPort() async throws {
        let app = FakeLaunchConfigurable()
        let scenario = StubScenario(routes: [.get("/ping", response: .status(200))])

        try await WireStubXCTestTestHelpers.withStartedServer(scenario: scenario) { wire in
            try wire.configure(app, baseURLEnvironmentKey: "API_BASE_URL")
            XCTAssertNotEqual(URL(string: app.launchEnvironment["API_BASE_URL"]!)?.port, 0)
        }
    }

    func testConfigureAppNeverInjectsPortZero() async throws {
        let app = FakeLaunchConfigurable()
        let scenario = StubScenario(routes: [.get("/ping", response: .status(200))])

        try await WireStubXCTestTestHelpers.withStartedServer(scenario: scenario) { wire in
            try wire.configure(app, baseURLEnvironmentKey: "API_BASE_URL")
            XCTAssertNotEqual(app.launchEnvironment["API_BASE_URL"], "http://127.0.0.1:0")
        }
    }
}
