import Foundation
import XCTest
@testable import WireStubXCTest
import WireStubServer
import WireStubCore

final class NoAppInjectionContractTests: XCTestCase {
    private final class FakeApp: WireStubLaunchConfigurable {
        var launchEnvironment: [String: String] = [:]
    }

    private func packageRoot() -> String {
        var url = URL(fileURLWithPath: #file)
        while url.path != "/" {
            url = url.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return url.path
            }
        }
        fatalError("Could not locate Package.swift")
    }

    func testXCTestConfigureOnlyInjectsBaseURLByDefault() async throws {
        let app = FakeApp()
        let scenario = StubScenario(routes: [.get("/ping", response: .status(200))])
        let server = try LocalStubServer(scenario: scenario)
        try await server.start()
        addTeardownBlock { [server] in
            await server.stop()
        }

        try server.configure(app)
        XCTAssertEqual(app.launchEnvironment.keys.sorted(), ["API_BASE_URL"])
        XCTAssertEqual(app.launchEnvironment["API_BASE_URL"], server.baseURL.absoluteString)
    }

    func testNoPublicAPIRequiresAppTargetToImportWireStubForServerReplay() throws {
        let source = try String(contentsOfFile: packageRoot() + "/Sources/WireStubServer/LocalStubServer.swift")
        XCTAssertFalse(source.contains("XCUIApplication"))
        XCTAssertFalse(source.contains("WireStubXCTest"))
    }

    func testServerReplayCanBeDrivenEntirelyFromTestProcess() async throws {
        let scenario = StubScenario(routes: [.get("/ping", response: .status(200))])
        let server = try LocalStubServer(scenario: scenario)
        try await server.start()
        addTeardownBlock { [server] in
            await server.stop()
        }

        var request = URLRequest(url: URL(string: "/ping", relativeTo: server.baseURL)!)
        request.httpMethod = "GET"
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    }

    func testDefaultUIReplayPolicyDoesNotIncludeHeaderSubset() {
        XCTAssertFalse(MatchingPolicy.defaultUIReplay.components.contains(.headerSubset))
    }
}
