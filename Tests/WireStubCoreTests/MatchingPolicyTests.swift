import XCTest
@testable import WireStubCore

final class MatchingPolicyTests: XCTestCase {

    func testDefaultUIReplayPolicyMatchesMethodPathAndQuerySubset() async throws {
        let route = StubRoute(
            matcher: RouteMatcher(
                method: "GET",
                path: "/search",
                queryItems: [QueryItem(name: "q", value: "swift")],
                policy: .defaultUIReplay
            ),
            responseProvider: .staticResponse(.status(200))
        )
        let scenario = StubScenario(routes: [route], replayStrategy: .firstMatch)
        let engine = StubEngine(scenario: scenario)

        let request = RequestSnapshot(
            method: "GET",
            path: "/search",
            queryItems: [QueryItem(name: "q", value: "swift"), QueryItem(name: "page", value: "2")]
        )
        let result = await engine.handle(request)
        guard case .matched = result else {
            return XCTFail("Default policy should match with extra query item present (querySubset)")
        }
    }

    func testDefaultUIReplayPolicyIgnoresHostSchemeAndPort() async throws {
        let route = StubRoute.get("/me", response: .status(200))
        let scenario = StubScenario(routes: [route], replayStrategy: .firstMatch)
        let engine = StubEngine(scenario: scenario)

        let request = RequestSnapshot(
            method: "GET",
            path: "/me",
            target: RequestTarget(scheme: "https", host: "prod.example.com", port: 443)
        )
        let result = await engine.handle(request)
        guard case .matched = result else {
            return XCTFail("Default policy must ignore scheme, host, and port")
        }
    }

    func testHeaderMatchingIsOptIn() async throws {
        // With default policy (no header component), mismatched headers should not affect matching
        let route = StubRoute.get("/me", response: .status(200))
        let scenario = StubScenario(routes: [route], replayStrategy: .firstMatch)
        let engine = StubEngine(scenario: scenario)

        let request = RequestSnapshot(
            method: "GET",
            path: "/me",
            headers: ["Authorization": "Bearer token123"]
        )
        let result = await engine.handle(request)
        guard case .matched = result else {
            return XCTFail("Header matching is opt-in; mismatched headers must not block default matching")
        }
    }

    func testQueryExactRequiresAllQueryItems() async throws {
        let policy = MatchingPolicy(components: [.method, .path, .queryExact])
        let route = StubRoute(
            matcher: RouteMatcher(
                method: "GET",
                path: "/search",
                queryItems: [QueryItem(name: "q", value: "swift")],
                policy: policy
            ),
            responseProvider: .staticResponse(.status(200))
        )
        let scenario = StubScenario(routes: [route], replayStrategy: .firstMatch)
        let engine = StubEngine(scenario: scenario)

        // Extra query item "page" should cause a mismatch under queryExact
        let request = RequestSnapshot(
            method: "GET",
            path: "/search",
            queryItems: [QueryItem(name: "q", value: "swift"), QueryItem(name: "page", value: "2")]
        )
        let result = await engine.handle(request)
        guard case .unmatched = result else {
            return XCTFail("queryExact should reject extra query items")
        }
    }

    func testQuerySubsetAllowsAdditionalVolatileQueryItems() async throws {
        let policy = MatchingPolicy(components: [.method, .path, .querySubset])
        let route = StubRoute(
            matcher: RouteMatcher(
                method: "GET",
                path: "/search",
                queryItems: [QueryItem(name: "q", value: "swift")],
                policy: policy
            ),
            responseProvider: .staticResponse(.status(200))
        )
        let scenario = StubScenario(routes: [route], replayStrategy: .firstMatch)
        let engine = StubEngine(scenario: scenario)

        let request = RequestSnapshot(
            method: "GET",
            path: "/search",
            queryItems: [
                QueryItem(name: "q", value: "swift"),
                QueryItem(name: "utm_source", value: "test"),
            ]
        )
        let result = await engine.handle(request)
        guard case .matched = result else {
            return XCTFail("querySubset should allow extra query items")
        }
    }

    func testIgnoredQueryItemsAreNotConsidered() async throws {
        let policy = MatchingPolicy(
            components: [.method, .path, .querySubset],
            ignoredQueryItems: ["utm_source"]
        )
        let route = StubRoute(
            matcher: RouteMatcher(
                method: "GET",
                path: "/landing",
                queryItems: [QueryItem(name: "ref", value: "home")],
                policy: policy
            ),
            responseProvider: .staticResponse(.status(200))
        )
        let scenario = StubScenario(routes: [route], replayStrategy: .firstMatch)
        let engine = StubEngine(scenario: scenario)

        let request = RequestSnapshot(
            method: "GET",
            path: "/landing",
            queryItems: [
                QueryItem(name: "ref", value: "home"),
                QueryItem(name: "utm_source", value: "newsletter"),
            ]
        )
        let result = await engine.handle(request)
        guard case .matched = result else {
            return XCTFail("Ignored query items must not contribute to matching")
        }
    }

    func testMethodMismatchProducesMethodMismatchReason() async throws {
        let route = StubRoute.post("/login", response: .status(200))
        let evaluation = RouteEvaluator.evaluate(
            route: route,
            against: RequestSnapshot(method: "GET", path: "/login"),
            scenarioPolicy: .defaultUIReplay
        )
        XCTAssertFalse(evaluation.isMatch)
        XCTAssertTrue(evaluation.reasons.contains {
            if case .methodMismatch = $0 { return true }
            return false
        })
    }

    func testPathMismatchProducesPathMismatchReason() async throws {
        let route = StubRoute.get("/expected", response: .status(200))
        let evaluation = RouteEvaluator.evaluate(
            route: route,
            against: RequestSnapshot(method: "GET", path: "/actual"),
            scenarioPolicy: .defaultUIReplay
        )
        XCTAssertFalse(evaluation.isMatch)
        XCTAssertTrue(evaluation.reasons.contains {
            if case .pathMismatch = $0 { return true }
            return false
        })
    }

    func testBodyMismatchProducesBodyMismatchReason() async throws {
        let policy = MatchingPolicy(components: [.method, .path, .bodyHash])
        let routeBody = "{\"action\":\"login\"}".data(using: .utf8)!
        let route = StubRoute(
            matcher: RouteMatcher(
                method: "POST",
                path: "/auth",
                body: routeBody,
                policy: policy
            ),
            responseProvider: .staticResponse(.status(200))
        )
        let requestBody = "{\"action\":\"logout\"}".data(using: .utf8)!
        let evaluation = RouteEvaluator.evaluate(
            route: route,
            against: RequestSnapshot(method: "POST", path: "/auth", body: requestBody),
            scenarioPolicy: .defaultUIReplay
        )
        XCTAssertFalse(evaluation.isMatch)
        XCTAssertTrue(evaluation.reasons.contains {
            if case .bodyHashMismatch = $0 { return true }
            return false
        })
    }

    func testQueryExactDistinguishesDuplicateQueryItems() async throws {
        let policy = MatchingPolicy(components: [.method, .path, .queryExact])
        let route = StubRoute(
            matcher: RouteMatcher(
                method: "GET",
                path: "/search",
                queryItems: [
                    QueryItem(name: "tag", value: "a"),
                    QueryItem(name: "tag", value: "b"),
                ],
                policy: policy
            ),
            responseProvider: .staticResponse(.status(200))
        )
        let engine = StubEngine(scenario: StubScenario(routes: [route]))

        let result = await engine.handle(
            RequestSnapshot(method: "GET", path: "/search", queryItems: [QueryItem(name: "tag", value: "a")])
        )
        guard case .unmatched = result else {
            return XCTFail("queryExact must distinguish duplicate query items")
        }
    }

    func testQuerySubsetRequiresExpectedDuplicateQueryItems() async throws {
        let policy = MatchingPolicy(components: [.method, .path, .querySubset])
        let route = StubRoute(
            matcher: RouteMatcher(
                method: "GET",
                path: "/search",
                queryItems: [
                    QueryItem(name: "tag", value: "a"),
                    QueryItem(name: "tag", value: "a"),
                ],
                policy: policy
            ),
            responseProvider: .staticResponse(.status(200))
        )
        let engine = StubEngine(scenario: StubScenario(routes: [route]))

        let result = await engine.handle(
            RequestSnapshot(method: "GET", path: "/search", queryItems: [QueryItem(name: "tag", value: "a")])
        )
        guard case .unmatched = result else {
            return XCTFail("querySubset must require each expected duplicate item")
        }
    }

    func testQuerySubsetAllowsAdditionalDuplicateQueryItems() async throws {
        let policy = MatchingPolicy(components: [.method, .path, .querySubset])
        let route = StubRoute(
            matcher: RouteMatcher(
                method: "GET",
                path: "/search",
                queryItems: [QueryItem(name: "tag", value: "a")],
                policy: policy
            ),
            responseProvider: .staticResponse(.status(200))
        )
        let engine = StubEngine(scenario: StubScenario(routes: [route]))

        let result = await engine.handle(
            RequestSnapshot(
                method: "GET",
                path: "/search",
                queryItems: [
                    QueryItem(name: "tag", value: "a"),
                    QueryItem(name: "tag", value: "a"),
                ]
            )
        )
        guard case .matched = result else {
            return XCTFail("querySubset must allow additional duplicate items")
        }
    }

    func testStubScenarioMatchingPolicyControlsMatching() async throws {
        let scenario = StubScenario(
            routes: [
                StubRoute(
                    matcher: RouteMatcher(method: "GET", path: "/headers", headers: ["X-Test": "required"]),
                    responseProvider: .staticResponse(.status(204))
                ),
            ],
            matchingPolicy: MatchingPolicy(components: [.method, .path, .headerSubset])
        )
        let engine = StubEngine(scenario: scenario)

        let unmatched = await engine.handle(
            RequestSnapshot(method: "GET", path: "/headers", headers: ["X-Test": "required"])
        )
        guard case .matched = unmatched else {
            return XCTFail("Scenario matching policy should apply to routes using the scenario default")
        }

        let mismatch = await engine.handle(
            RequestSnapshot(method: "GET", path: "/headers", headers: ["X-Test": "other"])
        )
        guard case .unmatched = mismatch else {
            return XCTFail("Scenario matching policy should change matching behavior")
        }
    }

    func testScenarioMatchingPolicyCanRequireCanonicalJSONBodyHash() async throws {
        let scenario = StubScenario(
            routes: [
                StubRoute(
                    matcher: RouteMatcher(method: "POST", path: "/submit", body: #"{"a":1,"b":2}"#.data(using: .utf8)!),
                    responseProvider: .staticResponse(.status(200))
                ),
            ],
            matchingPolicy: MatchingPolicy(components: [.method, .path, .canonicalJSONBodyHash])
        )
        let engine = StubEngine(scenario: scenario)

        let result = await engine.handle(
            RequestSnapshot(method: "POST", path: "/submit", body: #"{"b":2,"a":1}"#.data(using: .utf8)!)
        )
        guard case .matched = result else {
            return XCTFail("Scenario matching policy should require canonical JSON body hash when configured")
        }
    }

    func testScenarioMatchingPolicyCanUseHeaderSubsetWhenOptedIn() async throws {
        let scenario = StubScenario(
            routes: [
                StubRoute(
                    matcher: RouteMatcher(
                        method: "GET",
                        path: "/secure",
                        headers: ["X-Token": "abc123"]
                    ),
                    responseProvider: .staticResponse(.status(200))
                ),
            ],
            matchingPolicy: MatchingPolicy(components: [.method, .path, .headerSubset])
        )
        let engine = StubEngine(scenario: scenario)

        let result = await engine.handle(
            RequestSnapshot(method: "GET", path: "/secure", headers: ["x-token": "abc123"])
        )
        guard case .matched = result else {
            return XCTFail("Scenario matching policy should make header subset matching live")
        }
    }

    func testHeaderMatchingIsCaseInsensitive() async throws {
        let route = StubRoute(
            matcher: RouteMatcher(
                method: "GET",
                path: "/secure",
                headers: ["Authorization": "Bearer token"],
                policy: MatchingPolicy(components: [.method, .path, .headerSubset])
            ),
            responseProvider: .staticResponse(.status(200))
        )
        let engine = StubEngine(scenario: StubScenario(routes: [route]))

        let result = await engine.handle(
            RequestSnapshot(method: "GET", path: "/secure", headers: ["authorization": "Bearer token"])
        )
        guard case .matched = result else {
            return XCTFail("Header matching must be case insensitive")
        }
    }
}
