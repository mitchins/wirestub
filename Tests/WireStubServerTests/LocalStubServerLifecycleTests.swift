import XCTest
@testable import WireStubServer
import WireStubCore

final class LocalStubServerLifecycleTests: XCTestCase {
    func testServerStartsOnLoopbackAddress() async throws {
        let scenario = StubScenario(routes: [.get("/ping", response: .status(200))])

        try await ServerTestHelpers.withStartedServer(scenario: scenario) { server in
            XCTAssertEqual(server.baseURL.host, "127.0.0.1")
            XCTAssertNotNil(server.baseURL.port)
            XCTAssertNotEqual(server.baseURL.port, 0)
        }
    }

    func testServerChoosesDynamicAvailablePort() async throws {
        let scenario = StubScenario(routes: [.get("/ping", response: .status(200))])

        try await ServerTestHelpers.withStartedServer(scenario: scenario) { server in
            XCTAssertNotNil(server.baseURL.port)
            XCTAssertGreaterThan(server.baseURL.port ?? 0, 0)
        }
    }

    func testBaseURLUsesHTTPAnd127001() async throws {
        let scenario = StubScenario(routes: [.get("/ping", response: .status(200))])

        try await ServerTestHelpers.withStartedServer(scenario: scenario) { server in
            XCTAssertEqual(server.baseURL.scheme, "http")
            XCTAssertEqual(server.baseURL.host, "127.0.0.1")
        }
    }

    func testServerStopsAndReleasesPort() async throws {
        let scenario = StubScenario(routes: [.get("/ping", response: .status(200))])
        let server = try LocalStubServer(scenario: scenario)
        try await server.start()
        let port = try XCTUnwrap(server.baseURL.port)

        await server.stop()

        let bindable = await ServerTestHelpers.waitUntilPortIsBindable(port)
        XCTAssertTrue(bindable)
    }

    func testStartingTwiceIsIdempotentOrThrowsPredictably() async throws {
        let scenario = StubScenario(routes: [.get("/ping", response: .status(200))])
        let server = try LocalStubServer(scenario: scenario)
        try await server.start()
        addTeardownBlock { [server] in
            await server.stop()
        }

        do {
            try await server.start()
        } catch let error as LocalStubServerError {
            XCTAssertEqual(error, .alreadyStarted)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testRequestsAfterStopFailPredictably() async throws {
        let scenario = StubScenario(routes: [.get("/ping", response: .status(200))])
        let server = try LocalStubServer(scenario: scenario)
        try await server.start()
        let request = ServerTestHelpers.makeRequest(baseURL: server.baseURL, path: "/ping")
        _ = try await ServerTestHelpers.perform(request)

        await server.stop()

        do {
            _ = try await ServerTestHelpers.perform(request)
            XCTFail("Request after stop should fail")
        } catch let error as URLError {
            XCTAssertFalse(error.code == .unknown)
        } catch {
            XCTFail("Expected URLError after stop, got \(error)")
        }
    }

    func testStartReturnsOnlyWhenServerAcceptsRequests() async throws {
        let scenario = StubScenario(routes: [.get("/ping", response: .status(200))])
        let server = try LocalStubServer(scenario: scenario)
        try await server.start()
        let request = ServerTestHelpers.makeRequest(baseURL: server.baseURL, path: "/ping")
        let (response, _) = try await ServerTestHelpers.perform(request)
        XCTAssertEqual(response.statusCode, 200)
        await server.stop()
    }

    func testStopAwaitsTeardownAndPortStopsAcceptingRequests() async throws {
        let scenario = StubScenario(routes: [.get("/ping", response: .status(200))])
        let server = try LocalStubServer(scenario: scenario)
        try await server.start()
        let port = try XCTUnwrap(server.baseURL.port)

        await server.stop()

        let bindable = await ServerTestHelpers.waitUntilPortIsBindable(port)
        XCTAssertTrue(bindable)
        XCTAssertEqual(server.baseURL.port, 0)
    }

    func testStopIsIdempotent() async throws {
        let server = try LocalStubServer(scenario: StubScenario(routes: [.get("/ping", response: .status(200))]))
        try await server.start()
        await server.stop()
        await server.stop()
        XCTAssertFalse(server.isStarted)
    }

    func testStartStopRepeatedlyDoesNotLeakPorts() async throws {
        let scenario = StubScenario(routes: [.get("/ping", response: .status(200))])
        var ports: [Int] = []

        for _ in 0..<3 {
            let server = try LocalStubServer(scenario: scenario)
            try await server.start()
            ports.append(try XCTUnwrap(server.baseURL.port))
            await server.stop()
        }

        for port in ports {
            let bindable = await ServerTestHelpers.waitUntilPortIsBindable(port)
            XCTAssertTrue(bindable)
        }
    }

    func testServerCanRestartOrThrowsPredictablyAfterStop() async throws {
        let scenario = StubScenario(routes: [.get("/ping", response: .status(200))])
        let server = try LocalStubServer(scenario: scenario)
        try await server.start()
        await server.stop()

        try await server.start()
        addTeardownBlock { [server] in
            await server.stop()
        }
        let request = ServerTestHelpers.makeRequest(baseURL: server.baseURL, path: "/ping")
        let (response, _) = try await ServerTestHelpers.perform(request)
        XCTAssertEqual(response.statusCode, 200)
    }
}
