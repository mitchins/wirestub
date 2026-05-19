import XCTest
import WireStubCore
@testable import WireStubURLProtocol

final class URLProtocolIsolationTests: XCTestCase {
    func testSeparateURLSessionConfigurationsCanUseSeparateEngines() async throws {
        let baselineCount = URLProtocolEngineRegistry.shared.count
        let configA = URLSessionConfiguration.ephemeral
        let installationA = URLProtocolInstaller.install(
            scenario: StubScenario(routes: [.get("/status", response: .status(200))]),
            into: configA
        )
        let sessionA = URLSession(configuration: configA)
        defer {
            sessionA.invalidateAndCancel()
            installationA.invalidate()
        }

        let configB = URLSessionConfiguration.ephemeral
        let installationB = URLProtocolInstaller.install(
            scenario: StubScenario(routes: [.get("/status", response: .status(404))]),
            into: configB
        )
        let sessionB = URLSession(configuration: configB)
        defer {
            sessionB.invalidateAndCancel()
            installationB.invalidate()
        }

        XCTAssertEqual(URLProtocolEngineRegistry.shared.count, baselineCount + 2)

        let request = URLProtocolTestHelpers.makeRequest(path: "/status")
        let responseA = try await URLProtocolTestHelpers.perform(request, session: sessionA)
        let responseB = try await URLProtocolTestHelpers.perform(request, session: sessionB)
        let journalA = await installationA.engine.currentJournal()
        let journalB = await installationB.engine.currentJournal()

        XCTAssertEqual(responseA.0.statusCode, 200)
        XCTAssertEqual(responseB.0.statusCode, 404)
        XCTAssertEqual(journalA.entries.count, 1)
        XCTAssertEqual(journalB.entries.count, 1)
    }

    func testURLProtocolDoesNotRequireGlobalRouteTableForTestScopedSession() {
        let request = URLProtocolTestHelpers.makeRequest(path: "/status")
        XCTAssertFalse(WireStubURLProtocol.canInit(with: request))

        let configuration = URLSessionConfiguration.ephemeral
        let installation = URLProtocolInstaller.install(
            scenario: StubScenario(routes: [.get("/status", response: .status(200))]),
            into: configuration
        )
        defer { installation.invalidate() }
        XCTAssertTrue(configuration.protocolClasses?.first === WireStubURLProtocol.self)
    }

    func testURLProtocolStateDoesNotLeakBetweenTests() async throws {
        let scenario = StubScenario(
            routes: [.sequence(method: "GET", path: "/feed", responses: [.status(200), .status(201)])],
            replayStrategy: .firstMatch
        )

        try await URLProtocolTestHelpers.withInstalledSession(scenario: scenario) { session, _ in
            let request = URLProtocolTestHelpers.makeRequest(path: "/feed")
            let first = try await URLProtocolTestHelpers.perform(request, session: session)
            let second = try await URLProtocolTestHelpers.perform(request, session: session)
            XCTAssertEqual(first.0.statusCode, 200)
            XCTAssertEqual(second.0.statusCode, 201)
        }

        try await URLProtocolTestHelpers.withInstalledSession(scenario: scenario) { session, _ in
            let request = URLProtocolTestHelpers.makeRequest(path: "/feed")
            let first = try await URLProtocolTestHelpers.perform(request, session: session)
            XCTAssertEqual(first.0.statusCode, 200)
        }
    }

    func testURLProtocolSequenceStateIsIsolatedPerEngine() async throws {
        let scenario = StubScenario(
            routes: [.sequence(method: "GET", path: "/feed", responses: [.status(200), .status(201)])],
            replayStrategy: .firstMatch
        )

        let configA = URLSessionConfiguration.ephemeral
        let installationA = URLProtocolInstaller.install(scenario: scenario, into: configA)
        let sessionA = URLSession(configuration: configA)
        defer {
            sessionA.invalidateAndCancel()
            installationA.invalidate()
        }

        let configB = URLSessionConfiguration.ephemeral
        let installationB = URLProtocolInstaller.install(scenario: scenario, into: configB)
        let sessionB = URLSession(configuration: configB)
        defer {
            sessionB.invalidateAndCancel()
            installationB.invalidate()
        }

        let request = URLProtocolTestHelpers.makeRequest(path: "/feed")
        let firstA = try await URLProtocolTestHelpers.perform(request, session: sessionA)
        let firstB = try await URLProtocolTestHelpers.perform(request, session: sessionB)
        let secondA = try await URLProtocolTestHelpers.perform(request, session: sessionA)

        XCTAssertEqual(firstA.0.statusCode, 200)
        XCTAssertEqual(firstB.0.statusCode, 200)
        XCTAssertEqual(secondA.0.statusCode, 201)
    }

    func testURLProtocolInstallationCanBeInvalidated() async throws {
        let baselineCount = URLProtocolEngineRegistry.shared.count
        let configuration = URLSessionConfiguration.ephemeral
        let installation = URLProtocolInstaller.install(
            scenario: StubScenario(routes: [.get("/status", response: .status(200))]),
            into: configuration
        )
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let request = URLProtocolTestHelpers.makeRequest(path: "/status")
        let first = try await URLProtocolTestHelpers.perform(request, session: session)
        XCTAssertEqual(first.0.statusCode, 200)

        installation.invalidate()
        XCTAssertEqual(URLProtocolEngineRegistry.shared.count, baselineCount)

        do {
            _ = try await URLProtocolTestHelpers.perform(request, session: session)
            XCTFail("Invalidated installation should no longer route requests")
        } catch {
            XCTAssertEqual(URLProtocolEngineRegistry.shared.count, baselineCount)
        }
    }

    func testURLProtocolRegistryDoesNotRetainInvalidatedEngine() {
        let baselineCount = URLProtocolEngineRegistry.shared.count
        let configuration = URLSessionConfiguration.ephemeral
        let installation = URLProtocolInstaller.install(
            scenario: StubScenario(routes: [.get("/status", response: .status(200))]),
            into: configuration
        )
        XCTAssertEqual(URLProtocolEngineRegistry.shared.count, baselineCount + 1)
        installation.invalidate()
        XCTAssertEqual(URLProtocolEngineRegistry.shared.count, baselineCount)
    }

    func testURLProtocolStateDoesNotLeakAfterInvalidation() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        let installation = URLProtocolInstaller.install(
            scenario: StubScenario(routes: [.get("/status", response: .status(200))]),
            into: configuration
        )
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        _ = try await URLProtocolTestHelpers.perform(URLProtocolTestHelpers.makeRequest(path: "/status"), session: session)
        installation.invalidate()

        let secondConfiguration = URLSessionConfiguration.ephemeral
        let secondInstallation = URLProtocolInstaller.install(
            scenario: StubScenario(routes: [.get("/status", response: .status(201))]),
            into: secondConfiguration
        )
        let secondSession = URLSession(configuration: secondConfiguration)
        defer {
            secondSession.invalidateAndCancel()
            secondInstallation.invalidate()
        }

        let response = try await URLProtocolTestHelpers.perform(URLProtocolTestHelpers.makeRequest(path: "/status"), session: secondSession)
        XCTAssertEqual(response.0.statusCode, 201)
        let journal = await secondInstallation.engine.currentJournal()
        XCTAssertEqual(journal.entries.count, 1)
    }

    func testSeparateURLProtocolInstallationsRemainIsolatedAfterCleanup() async throws {
        let baselineCount = URLProtocolEngineRegistry.shared.count
        let configurationA = URLSessionConfiguration.ephemeral
        let installationA = URLProtocolInstaller.install(
            scenario: StubScenario(routes: [.get("/status", response: .status(200))]),
            into: configurationA
        )
        let sessionA = URLSession(configuration: configurationA)
        defer { sessionA.invalidateAndCancel() }

        let configurationB = URLSessionConfiguration.ephemeral
        let installationB = URLProtocolInstaller.install(
            scenario: StubScenario(routes: [.get("/status", response: .status(202))]),
            into: configurationB
        )
        let sessionB = URLSession(configuration: configurationB)
        defer {
            sessionB.invalidateAndCancel()
            installationB.invalidate()
        }

        installationA.invalidate()

        let result = try await URLProtocolTestHelpers.perform(URLProtocolTestHelpers.makeRequest(path: "/status"), session: sessionB)
        XCTAssertEqual(result.0.statusCode, 202)
        XCTAssertEqual(URLProtocolEngineRegistry.shared.count, baselineCount + 1)
    }
}
