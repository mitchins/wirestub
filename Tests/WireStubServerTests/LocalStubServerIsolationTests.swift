import XCTest
@testable import WireStubServer
import WireStubCore

final class LocalStubServerIsolationTests: XCTestCase {
    func testTwoServersUseDifferentPorts() async throws {
        let scenario = StubScenario(routes: [.get("/ping", response: .status(200))])
        let serverA = try LocalStubServer(scenario: scenario)
        let serverB = try LocalStubServer(scenario: scenario)
        try await serverA.start()
        try await serverB.start()
        addTeardownBlock { [serverA, serverB] in
            await serverA.stop()
            await serverB.stop()
        }

        XCTAssertNotEqual(serverA.baseURL.port, serverB.baseURL.port)
    }

    func testTwoServersDoNotShareJournals() async throws {
        let scenario = StubScenario(routes: [.get("/ping", response: .status(200))])
        let serverA = try LocalStubServer(scenario: scenario)
        let serverB = try LocalStubServer(scenario: scenario)
        try await serverA.start()
        try await serverB.start()
        addTeardownBlock { [serverA, serverB] in
            await serverA.stop()
            await serverB.stop()
        }

        _ = try await ServerTestHelpers.perform(ServerTestHelpers.makeRequest(baseURL: serverA.baseURL, path: "/ping"))

        let journalA = await serverA.journal()
        let journalB = await serverB.journal()
        XCTAssertEqual(journalA.entries.count, 1)
        XCTAssertEqual(journalB.entries.count, 0)
    }

    func testTwoServersDoNotShareSequenceState() async throws {
        let route = StubRoute.sequence(method: "GET", path: "/seq", responses: [.status(200), .status(201)])
        let scenario = StubScenario(routes: [route])
        let serverA = try LocalStubServer(scenario: scenario)
        let serverB = try LocalStubServer(scenario: scenario)
        try await serverA.start()
        try await serverB.start()
        addTeardownBlock { [serverA, serverB] in
            await serverA.stop()
            await serverB.stop()
        }

        let a1 = try await ServerTestHelpers.perform(ServerTestHelpers.makeRequest(baseURL: serverA.baseURL, path: "/seq"))
        let b1 = try await ServerTestHelpers.perform(ServerTestHelpers.makeRequest(baseURL: serverB.baseURL, path: "/seq"))
        let a2 = try await ServerTestHelpers.perform(ServerTestHelpers.makeRequest(baseURL: serverA.baseURL, path: "/seq"))
        let b2 = try await ServerTestHelpers.perform(ServerTestHelpers.makeRequest(baseURL: serverB.baseURL, path: "/seq"))

        XCTAssertEqual(a1.0.statusCode, 200)
        XCTAssertEqual(b1.0.statusCode, 200)
        XCTAssertEqual(a2.0.statusCode, 201)
        XCTAssertEqual(b2.0.statusCode, 201)
    }

    func testTwoServersCanRunConcurrently() async throws {
        let scenarioA = StubScenario(routes: [.get("/a", response: .status(200))])
        let scenarioB = StubScenario(routes: [.get("/b", response: .status(201))])
        let serverA = try LocalStubServer(scenario: scenarioA)
        let serverB = try LocalStubServer(scenario: scenarioB)
        try await serverA.start()
        try await serverB.start()
        addTeardownBlock { [serverA, serverB] in
            await serverA.stop()
            await serverB.stop()
        }

        async let requestA = ServerTestHelpers.perform(ServerTestHelpers.makeRequest(baseURL: serverA.baseURL, path: "/a"))
        async let requestB = ServerTestHelpers.perform(ServerTestHelpers.makeRequest(baseURL: serverB.baseURL, path: "/b"))
        let (a, b) = try await (requestA, requestB)

        XCTAssertEqual(a.0.statusCode, 200)
        XCTAssertEqual(b.0.statusCode, 201)
    }

    func testParallelRequestsToDifferentServersRemainIsolated() async throws {
        let scenarioA = StubScenario(routes: [.get("/a", response: .status(200))])
        let scenarioB = StubScenario(routes: [.get("/b", response: .status(201))])
        let serverA = try LocalStubServer(scenario: scenarioA)
        let serverB = try LocalStubServer(scenario: scenarioB)
        try await serverA.start()
        try await serverB.start()
        addTeardownBlock { [serverA, serverB] in
            await serverA.stop()
            await serverB.stop()
        }

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    _ = try? await ServerTestHelpers.perform(ServerTestHelpers.makeRequest(baseURL: serverA.baseURL, path: "/a"))
                }
                group.addTask {
                    _ = try? await ServerTestHelpers.perform(ServerTestHelpers.makeRequest(baseURL: serverB.baseURL, path: "/b"))
                }
            }
        }

        let journalA = await serverA.journal()
        let journalB = await serverB.journal()
        XCTAssertEqual(journalA.entries.count, 10)
        XCTAssertEqual(journalB.entries.count, 10)
        XCTAssertEqual(Set(journalA.entries.map(\ .request.path)), ["/a"])
        XCTAssertEqual(Set(journalB.entries.map(\ .request.path)), ["/b"])
    }
}
