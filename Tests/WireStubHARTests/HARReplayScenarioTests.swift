import XCTest
@testable import WireStubHAR
import WireStubCore

final class HARReplayScenarioTests: XCTestCase {
    func testSimpleGetHARReplaysThroughCoreEngine() async throws {
        let archive = try HARTestHelpers.fixtureArchive("simple_get.har")
        let scenario = try HARNormalizer.scenario(from: archive)
        let engine = StubEngine(scenario: scenario)
        let result = await engine.handle(.harGet("/users"))
        guard case .matched(let response, _) = result else { return XCTFail("Expected match") }
        XCTAssertEqual(response.status, 200)
    }

    func testPostJSONHARMatchesCanonicalJSONBody() async throws {
        let archive = try HARTestHelpers.fixtureArchive("post_json.har")
        let scenario = try HARNormalizer.scenario(from: archive)
        let engine = StubEngine(scenario: scenario)
        let body = Data(#"{"role":"admin","name":"Blob"}"#.utf8)
        let result = await engine.handle(.harPost("/users", headers: ["Content-Type": "application/json"], body: body))
        guard case .matched(let response, _) = result else { return XCTFail("Expected canonical JSON body match") }
        XCTAssertEqual(response.status, 201)
    }

    func testRepeatedEndpointHARWorksInOrderedReplay() async throws {
        let archive = try HARTestHelpers.fixtureArchive("repeated_endpoint_ordered.har")
        let scenario = try HARNormalizer.scenario(from: archive)
        let engine = StubEngine(scenario: scenario)
        let first = await engine.handle(.harGet("/status"))
        let second = await engine.handle(.harGet("/status"))
        let third = await engine.handle(.harGet("/status"))
        let statuses = [first, second, third].compactMap { result -> Int? in
            if case .matched(let response, _) = result { return response.status }
            return nil
        }
        XCTAssertEqual(statuses, [202, 202, 200])
    }

    func testHARScenarioProducesSameJournalAsInlineScenario() async throws {
        let archive = try HARTestHelpers.fixtureArchive("simple_get.har")
        let harScenario = try HARNormalizer.scenario(from: archive)
        let inlineScenario = StubScenario(routes: [
            StubRoute(
                id: "har:entry:0",
                matcher: RouteMatcher(method: "GET", path: "/users"),
                responseProvider: .staticResponse(try StubResponse.json(["id": 1, "name": "Blob"]))
            )
        ], replayStrategy: .ordered)

        let harEngine = StubEngine(scenario: harScenario)
        let inlineEngine = StubEngine(scenario: inlineScenario)
        _ = await harEngine.handle(.harGet("/users"))
        _ = await inlineEngine.handle(.harGet("/users"))
        let harJournal = await harEngine.currentJournal()
        let inlineJournal = await inlineEngine.currentJournal()
        XCTAssertEqual(harJournal.entries.map(\.request.path), inlineJournal.entries.map(\.request.path))
        XCTAssertEqual(harJournal.entries.count, inlineJournal.entries.count)
    }

    func testHARUnmatchedRequestProducesCoreDiagnostic() async throws {
        let archive = try HARTestHelpers.fixtureArchive("simple_get.har")
        let scenario = try HARNormalizer.scenario(from: archive)
        let engine = StubEngine(scenario: scenario)
        let result = await engine.handle(.harGet("/missing"))
        guard case .unmatched(let diagnostic) = result else { return XCTFail("Expected unmatched") }
        XCTAssertTrue(diagnostic.render().contains("/missing"))
    }

    func testHARAndInlineScenarioProduceEquivalentReplayBehaviour() async throws {
        let archive = try HARTestHelpers.fixtureArchive("query_params.har")
        let harScenario = try HARNormalizer.scenario(from: archive)
        let inlineRoute = StubRoute(
            id: "har:entry:0",
            matcher: RouteMatcher(
                method: "GET",
                path: "/search",
                queryItems: [QueryItem(name: "q", value: "swift")],
                policy: .defaultUIReplay
            ),
            responseProvider: .staticResponse(.text("results"))
        )
        let inlineScenario = StubScenario(routes: [inlineRoute], replayStrategy: .ordered)
        let request = RequestSnapshot.harGet("/search", queryItems: [QueryItem(name: "q", value: "swift"), QueryItem(name: "page", value: "2")])

        let harEngine = StubEngine(scenario: harScenario)
        let inlineEngine = StubEngine(scenario: inlineScenario)
        let harResult = await harEngine.handle(request)
        let inlineResult = await inlineEngine.handle(request)

        switch (harResult, inlineResult) {
        case (.matched(let a, _), .matched(let b, _)):
            XCTAssertEqual(a.status, b.status)
            XCTAssertEqual(a.body, b.body)
        default:
            XCTFail("Expected equivalent matches")
        }
    }
}
