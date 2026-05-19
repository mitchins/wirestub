import XCTest
@testable import WireStubCore

final class BuilderAPITests: XCTestCase {

    func testGetBuilderCreatesMethodAndPathMatcher() {
        let route = StubRoute.get("/items", response: .status(200))
        XCTAssertEqual(route.matcher.method, "GET")
        XCTAssertEqual(route.matcher.path, "/items")
    }

    func testPostBuilderCreatesMethodAndPathMatcher() {
        let route = StubRoute.post("/items", response: .status(201))
        XCTAssertEqual(route.matcher.method, "POST")
        XCTAssertEqual(route.matcher.path, "/items")
    }

    func testBuilderCanSetStableRouteIdentifier() {
        let route = StubRoute.get("/items", matching: .init(id: "feed-list"), response: .status(200))
        XCTAssertEqual(route.id, "feed-list")
    }

    func testNamedBuilderProvidesStableIdentifier() {
        let route = StubRoute.get("/items", response: .status(200)).named("feed-list")
        XCTAssertEqual(route.id, "feed-list")
    }

    func testGetBuilderInfersHeaderAndQueryMatching() {
        let route = StubRoute.get(
            "/me",
            matching: .init(
                queryItems: [QueryItem(name: "include", value: "profile")],
                headers: ["Authorization": "Bearer token"]
            ),
            response: .status(200)
        )
        XCTAssertEqual(route.matcher.queryItems, [QueryItem(name: "include", value: "profile")])
        XCTAssertEqual(route.matcher.headers["Authorization"], "Bearer token")
        XCTAssertTrue(route.matcher.policy.components.contains(.headerSubset))
        XCTAssertTrue(route.matcher.policy.components.contains(.querySubset))
        XCTAssertFalse(route.matcher.usesScenarioMatchingPolicy)
    }

    func testPostBuilderInfersBodyHashMatching() {
        let body = #"{"refresh":"stale"}"#.data(using: .utf8)!
        let route = StubRoute.post(
            "/auth/refresh",
            matching: .init(
                headers: ["Authorization": "Bearer stale-token"],
                body: body
            ),
            response: .status(401)
        )
        XCTAssertEqual(route.matcher.body, body)
        XCTAssertTrue(route.matcher.policy.components.contains(.headerSubset))
        XCTAssertTrue(route.matcher.policy.components.contains(.bodyHash))
    }

    func testPostJSONBuilderInfersCanonicalJSONBodyMatching() throws {
        let route = try StubRoute.post(
            "/auth/refresh",
            matching: .init(headers: ["Authorization": "Bearer stale-token"]),
            jsonBody: ["refreshToken": "stale"],
            response: .status(401)
        )
        XCTAssertEqual(route.matcher.headers["Authorization"], "Bearer stale-token")
        XCTAssertNotNil(route.matcher.body)
        XCTAssertTrue(route.matcher.policy.components.contains(.headerSubset))
        XCTAssertTrue(route.matcher.policy.components.contains(.canonicalJSONBodyHash))
    }

    func testPutBuilderSupportsBodyMatching() {
        let body = Data("blob".utf8)
        let route = StubRoute.put("/profile", matching: .init(body: body), response: .status(200))
        XCTAssertEqual(route.matcher.method, "PUT")
        XCTAssertEqual(route.matcher.body, body)
        XCTAssertTrue(route.matcher.policy.components.contains(.bodyHash))
    }

    func testPatchJSONBuilderSupportsCanonicalBodyMatching() throws {
        let route = try StubRoute.patch("/profile", jsonBody: ["name": "Blob"], response: .status(200))
        XCTAssertEqual(route.matcher.method, "PATCH")
        XCTAssertNotNil(route.matcher.body)
        XCTAssertTrue(route.matcher.policy.components.contains(.canonicalJSONBodyHash))
    }

    func testDeleteBuilderSupportsHeadersAndQueryItems() {
        let route = StubRoute.delete(
            "/account",
            matching: .init(
                queryItems: [QueryItem(name: "force", value: "true")],
                headers: ["Authorization": "Bearer token"]
            ),
            response: .status(204)
        )
        XCTAssertEqual(route.matcher.method, "DELETE")
        XCTAssertEqual(route.matcher.queryItems, [QueryItem(name: "force", value: "true")])
        XCTAssertEqual(route.matcher.headers["Authorization"], "Bearer token")
        XCTAssertTrue(route.matcher.policy.components.contains(.headerSubset))
    }

    func testSequenceBuilderCanIncludeStableIDAndHeaders() {
        let route = StubRoute.sequence(
            method: "GET",
            path: "/notifications",
            matching: .init(
                id: "notifications-sequence",
                headers: ["Authorization": "Bearer token"]
            ),
            responses: [.status(200), .status(401)]
        )
        XCTAssertEqual(route.id, "notifications-sequence")
        XCTAssertEqual(route.matcher.headers["Authorization"], "Bearer token")
        XCTAssertTrue(route.matcher.policy.components.contains(.headerSubset))
    }

    func testJsonResponseBuilderSetsContentType() throws {
        let response = try StubResponse.json(["key": "value"])
        XCTAssertEqual(response.headers["Content-Type"], "application/json")
        XCTAssertFalse(response.body.isEmpty)
    }

    func testTextResponseBuilderSetsContentType() {
        let response = StubResponse.text("hello")
        XCTAssertEqual(response.headers["Content-Type"], "text/plain; charset=utf-8")
        XCTAssertEqual(response.body, "hello".data(using: .utf8))
    }

    func testTextResponseBuilderUsesRequestedCharset() {
        let response = StubResponse.text("café", encoding: .isoLatin1)
        XCTAssertEqual(response.headers["Content-Type"], "text/plain; charset=iso-8859-1")
        XCTAssertEqual(response.body, "café".data(using: .isoLatin1))
    }

    func testStatusBuilderHasEmptyBodyByDefault() {
        let response = StubResponse.status(204)
        XCTAssertEqual(response.status, 204)
        XCTAssertTrue(response.body.isEmpty)
    }

    func testSequenceBuilderDefaultsToFailOnExhaustion() {
        let route = StubRoute.sequence(
            method: "GET",
            path: "/items",
            responses: [.status(200)]
        )
        guard case .sequence(_, let exhaustion) = route.responseProvider else {
            return XCTFail("Expected sequence provider")
        }
        XCTAssertEqual(exhaustion, .fail, "Default sequence exhaustion must be .fail")
    }
}
