import XCTest
@testable import WireStubHAR
import WireStubCore

final class HARNormalizationTests: XCTestCase {
    func testHARNormalizesEntriesIntoStubScenario() throws {
        let archive = try HARTestHelpers.fixtureArchive("simple_get.har")
        let scenario = try HARNormalizer.scenario(from: archive)
        XCTAssertEqual(scenario.routes.count, 1)
        XCTAssertEqual(scenario.routes.first?.id, "har:entry:0")
    }

    func testHARImportUsesPathBasedMatchingByDefault() throws {
        let archive = try HARTestHelpers.fixtureArchive("simple_get.har")
        let scenario = try HARNormalizer.scenario(from: archive)
        let route = try XCTUnwrap(scenario.routes.first)
        XCTAssertEqual(route.matcher.path, "/users")
        XCTAssertEqual(route.matcher.policy.components, [.method, .path, .querySubset])
    }

    func testHARImportDoesNotRequireOriginalHostInUIReplayMode() async throws {
        let archive = try HARTestHelpers.fixtureArchive("simple_get.har")
        let scenario = try HARNormalizer.scenario(from: archive)
        let engine = StubEngine(scenario: scenario)
        let result = await engine.handle(.harGet("/users"))
        guard case .matched(let response, _) = result else { return XCTFail("Expected match") }
        XCTAssertEqual(response.status, 200)
    }

    func testHARImportPreservesRepeatedRequestsInOrder() throws {
        let archive = try HARTestHelpers.fixtureArchive("repeated_endpoint_ordered.har")
        let scenario = try HARNormalizer.scenario(from: archive)
        XCTAssertEqual(scenario.replayStrategy, .ordered)
        XCTAssertEqual(scenario.routes.map(\.id), ["har:entry:0", "har:entry:1", "har:entry:2"])
    }

    func testHARImportIgnoresVolatileHeadersByDefault() throws {
        let archive = try HARTestHelpers.fixtureArchive("simple_get.har")
        let scenario = try HARNormalizer.scenario(from: archive)
        let route = try XCTUnwrap(scenario.routes.first)
        XCTAssertTrue(route.matcher.headers.isEmpty)
    }

    func testHARImportCanIncludeHeaderMatchingWhenRequested() async throws {
        let archive = try HARTestHelpers.fixtureArchive("simple_get.har")
        var options = HARImportOptions.standard
        options.includeHeaderMatching = true
        let scenario = try HARNormalizer.scenario(from: archive, options: options)
        let route = try XCTUnwrap(scenario.routes.first)
        XCTAssertTrue(route.matcher.policy.components.contains(.headerSubset))

        let engine = StubEngine(scenario: scenario)
        let matched = await engine.handle(.harGet("/users", headers: ["Accept": "application/json"]))
        let unmatched = await engine.handle(.harGet("/users", headers: ["Accept": "text/plain"]))
        if case .matched = matched {} else { XCTFail("Expected header match") }
        if case .unmatched = unmatched {} else { XCTFail("Expected header mismatch") }
    }

    func testHARImportCanStripCookiesFromResponses() throws {
        let archive = try HARTestHelpers.fixtureArchive("sensitive_headers.har")
        var options = HARImportOptions.standard
        options.stripCookies = true
        let scenario = try HARNormalizer.scenario(from: archive, options: options)
        let route = try XCTUnwrap(scenario.routes.first)
        guard case .staticResponse(let response) = route.responseProvider else { return XCTFail("Expected static response") }
        XCTAssertNil(response.headers["Set-Cookie"])
    }

    func testHARImportPreservesDuplicateQueryItems() throws {
        let data = Data(#"{"log":{"entries":[{"request":{"method":"GET","url":"https://api.example.com/search?tag=a&tag=b","headers":[],"queryString":[{"name":"tag","value":"a"},{"name":"tag","value":"b"}]},"response":{"status":200,"headers":[],"content":{"mimeType":"application/json","text":"{}"}}}]}}"#.utf8)
        let archive = try HARLoader.load(data: data)
        let scenario = try HARNormalizer.scenario(from: archive)
        let route = try XCTUnwrap(scenario.routes.first)
        XCTAssertEqual(route.matcher.queryItems, [QueryItem(name: "tag", value: "a"), QueryItem(name: "tag", value: "b")])
    }
}
