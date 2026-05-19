import XCTest
@testable import WireStubServer
import WireStubCore

final class LocalStubServerJournalTests: XCTestCase {
    func testServerJournalRecordsRealHTTPRequests() async throws {
        let scenario = StubScenario(routes: [.get("/feed", response: .status(200))])

        try await ServerTestHelpers.withStartedServer(scenario: scenario) { server in
            _ = try await ServerTestHelpers.perform(ServerTestHelpers.makeRequest(baseURL: server.baseURL, path: "/feed"))
            let journal = await server.journal()
            XCTAssertEqual(journal.entries.count, 1)
            XCTAssertEqual(journal.entries.first?.request.path, "/feed")
        }
    }

    func testServerJournalPreservesOrder() async throws {
        let scenario = StubScenario(
            routes: [
                .get("/a", response: .status(200)),
                .get("/b", response: .status(201)),
            ],
            replayStrategy: .firstMatch
        )

        try await ServerTestHelpers.withStartedServer(scenario: scenario) { server in
            _ = try await ServerTestHelpers.perform(ServerTestHelpers.makeRequest(baseURL: server.baseURL, path: "/a"))
            _ = try await ServerTestHelpers.perform(ServerTestHelpers.makeRequest(baseURL: server.baseURL, path: "/b"))
            let journal = await server.journal()
            XCTAssertEqual(journal.entries.map(\ .request.path), ["/a", "/b"])
        }
    }

    func testServerJournalIncludesMatchedRouteIDs() async throws {
        let route = StubRoute.get("/route", response: .status(200))
        let scenario = StubScenario(routes: [route])

        try await ServerTestHelpers.withStartedServer(scenario: scenario) { server in
            _ = try await ServerTestHelpers.perform(ServerTestHelpers.makeRequest(baseURL: server.baseURL, path: "/route"))
            let journal = await server.journal()
            guard case .matched(let routeID, _) = journal.entries.first?.outcome else {
                return XCTFail("Expected matched journal outcome")
            }
            XCTAssertEqual(routeID, route.id)
        }
    }

    func testServerJournalCanBeReadAfterServerStops() async throws {
        let scenario = StubScenario(routes: [.get("/done", response: .status(200))])
        let server = try LocalStubServer(scenario: scenario)
        try await server.start()
        _ = try await ServerTestHelpers.perform(ServerTestHelpers.makeRequest(baseURL: server.baseURL, path: "/done"))
        await server.stop()

        let journal = await server.journal()
        XCTAssertEqual(journal.entries.count, 1)
        XCTAssertEqual(journal.entries.first?.request.path, "/done")
    }

    func testServerJournalIncludesUnmatchedRequests() async throws {
        let scenario = StubScenario(routes: [.get("/known", response: .status(200))], mode: .strict)

        try await ServerTestHelpers.withStartedServer(scenario: scenario) { server in
            _ = try await ServerTestHelpers.perform(ServerTestHelpers.makeRequest(baseURL: server.baseURL, path: "/unknown"))
            let journal = await server.journal()
            XCTAssertEqual(journal.unmatchedEntries.count, 1)
            XCTAssertEqual(journal.unmatchedEntries.first?.request.path, "/unknown")
        }
    }
}
