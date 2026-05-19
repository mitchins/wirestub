import Foundation

// MARK: - RouteMetadata

/// Optional source metadata attached to a route.
public struct RouteMetadata: Sendable, Equatable {
    /// Optional source file description for this route.
    public var sourceFile: String?
    /// Optional source entry index for this route.
    public var sourceEntry: Int?

    /// Creates route metadata for diagnostics and traceability.
    public init(sourceFile: String? = nil, sourceEntry: Int? = nil) {
        self.sourceFile = sourceFile
        self.sourceEntry = sourceEntry
    }
}

// MARK: - RouteMatcher

/// Defines what a route matches against.
public struct RouteMatcher: Sendable, Equatable {
    /// HTTP method to match.
    public var method: HTTPMethod
    /// Path to match.
    public var path: String
    /// Query items to match.
    public var queryItems: [QueryItem]
    /// Headers to match when header matching is enabled.
    public var headers: HTTPHeaders
    /// Optional body to match.
    public var body: Data?
    /// Explicit matching policy when not inheriting from the scenario.
    public var policy: MatchingPolicy
    /// Whether this matcher should inherit `StubScenario.matchingPolicy`.
    public var usesScenarioMatchingPolicy: Bool

    /// Creates a matcher that inherits the scenario matching policy.
    public init(
        method: HTTPMethod,
        path: String,
        queryItems: [QueryItem] = [],
        headers: HTTPHeaders = [:],
        body: Data? = nil
    ) {
        self.method = method.uppercased()
        self.path = path
        self.queryItems = queryItems
        self.headers = headers
        self.body = body
        self.policy = .defaultUIReplay
        self.usesScenarioMatchingPolicy = true
    }

    /// Creates a matcher with an explicit per-route matching policy.
    public init(
        method: HTTPMethod,
        path: String,
        queryItems: [QueryItem] = [],
        headers: HTTPHeaders = [:],
        body: Data? = nil,
        policy: MatchingPolicy
    ) {
        self.method = method.uppercased()
        self.path = path
        self.queryItems = queryItems
        self.headers = headers
        self.body = body
        self.policy = policy
        self.usesScenarioMatchingPolicy = false
    }
}

// MARK: - StubRoute

/// A single replayable route in a scenario.
public struct StubRoute: Sendable {
    /// Stable route identifier used in journals and diagnostics.
    public var id: String
    /// Matching definition for the route.
    public var matcher: RouteMatcher
    /// Response source used when the route matches.
    public var responseProvider: ResponseProvider
    /// Optional source metadata.
    public var metadata: RouteMetadata

    /// Creates a replayable route.
    public init(
        id: String = UUID().uuidString,
        matcher: RouteMatcher,
        responseProvider: ResponseProvider,
        metadata: RouteMetadata = RouteMetadata()
    ) {
        self.id = id
        self.matcher = matcher
        self.responseProvider = responseProvider
        self.metadata = metadata
    }
}

/// Common route-matching options for high-level route builders.
public struct RouteRequestOptions: Sendable, Equatable {
    /// Stable route identifier used in journals and diagnostics.
    public var id: String?
    /// Query items to match.
    public var queryItems: [QueryItem]
    /// Headers to match.
    public var headers: HTTPHeaders
    /// Raw body to match when using byte-hash builders.
    public var body: Data?
    /// Explicit matching policy override.
    public var policy: MatchingPolicy?

    /// Creates grouped matching options for route builders.
    public init(
        id: String? = nil,
        queryItems: [QueryItem] = [],
        headers: HTTPHeaders = [:],
        body: Data? = nil,
        policy: MatchingPolicy? = nil
    ) {
        self.id = id
        self.queryItems = queryItems
        self.headers = headers
        self.body = body
        self.policy = policy
    }
}

// MARK: - Builder helpers

/// Convenience builders for common route shapes.
public extension StubRoute {
    /// Convenience builder for a GET route with a static response.
    static func get(
        _ path: String,
        matching: RouteRequestOptions = RouteRequestOptions(),
        response: StubResponse
    ) -> StubRoute {
        route(
            descriptor: RouteDescriptor(
                id: matching.id,
                method: "GET",
                path: path,
                queryItems: matching.queryItems,
                headers: matching.headers,
                body: nil,
                policy: matching.policy,
                bodyMatchComponent: nil
            ),
            responseProvider: .staticResponse(response)
        )
    }

    /// Convenience builder for a POST route with a static response.
    static func post(
        _ path: String,
        matching: RouteRequestOptions = RouteRequestOptions(),
        response: StubResponse
    ) -> StubRoute {
        route(
            descriptor: RouteDescriptor(
                id: matching.id,
                method: "POST",
                path: path,
                queryItems: matching.queryItems,
                headers: matching.headers,
                body: matching.body,
                policy: matching.policy,
                bodyMatchComponent: matching.body == nil ? nil : .bodyHash
            ),
            responseProvider: .staticResponse(response)
        )
    }

    /// Convenience builder for a POST route with canonical-JSON body matching.
    static func post<Body: Encodable>(
        _ path: String,
        matching: RouteRequestOptions = RouteRequestOptions(),
        jsonBody: Body,
        encoder: JSONEncoder = JSONEncoder(),
        response: StubResponse
    ) throws -> StubRoute {
        route(
            descriptor: RouteDescriptor(
                id: matching.id,
                method: "POST",
                path: path,
                queryItems: matching.queryItems,
                headers: matching.headers,
                body: try encoder.encode(jsonBody),
                policy: matching.policy,
                bodyMatchComponent: .canonicalJSONBodyHash
            ),
            responseProvider: .staticResponse(response)
        )
    }

    /// Convenience builder for a PUT route with a static response.
    static func put(
        _ path: String,
        matching: RouteRequestOptions = RouteRequestOptions(),
        response: StubResponse
    ) -> StubRoute {
        route(
            descriptor: RouteDescriptor(
                id: matching.id,
                method: "PUT",
                path: path,
                queryItems: matching.queryItems,
                headers: matching.headers,
                body: matching.body,
                policy: matching.policy,
                bodyMatchComponent: matching.body == nil ? nil : .bodyHash
            ),
            responseProvider: .staticResponse(response)
        )
    }

    /// Convenience builder for a PUT route with canonical-JSON body matching.
    static func put<Body: Encodable>(
        _ path: String,
        matching: RouteRequestOptions = RouteRequestOptions(),
        jsonBody: Body,
        encoder: JSONEncoder = JSONEncoder(),
        response: StubResponse
    ) throws -> StubRoute {
        route(
            descriptor: RouteDescriptor(
                id: matching.id,
                method: "PUT",
                path: path,
                queryItems: matching.queryItems,
                headers: matching.headers,
                body: try encoder.encode(jsonBody),
                policy: matching.policy,
                bodyMatchComponent: .canonicalJSONBodyHash
            ),
            responseProvider: .staticResponse(response)
        )
    }

    /// Convenience builder for a PATCH route with a static response.
    static func patch(
        _ path: String,
        matching: RouteRequestOptions = RouteRequestOptions(),
        response: StubResponse
    ) -> StubRoute {
        route(
            descriptor: RouteDescriptor(
                id: matching.id,
                method: "PATCH",
                path: path,
                queryItems: matching.queryItems,
                headers: matching.headers,
                body: matching.body,
                policy: matching.policy,
                bodyMatchComponent: matching.body == nil ? nil : .bodyHash
            ),
            responseProvider: .staticResponse(response)
        )
    }

    /// Convenience builder for a PATCH route with canonical-JSON body matching.
    static func patch<Body: Encodable>(
        _ path: String,
        matching: RouteRequestOptions = RouteRequestOptions(),
        jsonBody: Body,
        encoder: JSONEncoder = JSONEncoder(),
        response: StubResponse
    ) throws -> StubRoute {
        route(
            descriptor: RouteDescriptor(
                id: matching.id,
                method: "PATCH",
                path: path,
                queryItems: matching.queryItems,
                headers: matching.headers,
                body: try encoder.encode(jsonBody),
                policy: matching.policy,
                bodyMatchComponent: .canonicalJSONBodyHash
            ),
            responseProvider: .staticResponse(response)
        )
    }

    /// Convenience builder for a DELETE route with a static response.
    static func delete(
        _ path: String,
        matching: RouteRequestOptions = RouteRequestOptions(),
        response: StubResponse
    ) -> StubRoute {
        route(
            descriptor: RouteDescriptor(
                id: matching.id,
                method: "DELETE",
                path: path,
                queryItems: matching.queryItems,
                headers: matching.headers,
                body: nil,
                policy: matching.policy,
                bodyMatchComponent: nil
            ),
            responseProvider: .staticResponse(response)
        )
    }

    /// Convenience builder for a route with a sequence of responses.
    static func sequence(
        method: String,
        path: String,
        matching: RouteRequestOptions = RouteRequestOptions(),
        responses: [StubResponse],
        exhaustion: SequenceExhaustion = .fail
    ) -> StubRoute {
        route(
            descriptor: RouteDescriptor(
                id: matching.id,
                method: method,
                path: path,
                queryItems: matching.queryItems,
                headers: matching.headers,
                body: matching.body,
                policy: matching.policy,
                bodyMatchComponent: matching.body == nil ? nil : .bodyHash
            ),
            responseProvider: .sequence(responses, exhaustion: exhaustion)
        )
    }

    /// Returns a copy of the route with a stable identifier.
    func named(_ id: String) -> StubRoute {
        var copy = self
        copy.id = id
        return copy
    }
}

private extension StubRoute {
    struct RouteDescriptor {
        let id: String?
        let method: HTTPMethod
        let path: String
        let queryItems: [QueryItem]
        let headers: HTTPHeaders
        let body: Data?
        let policy: MatchingPolicy?
        let bodyMatchComponent: MatchComponent?
    }

    static func route(
        descriptor: RouteDescriptor,
        responseProvider: ResponseProvider
    ) -> StubRoute {
        let resolvedPolicy = descriptor.policy ?? inferredPolicy(
            headers: descriptor.headers,
            bodyMatchComponent: descriptor.bodyMatchComponent
        )
        let matcher = RouteMatcher(
            method: descriptor.method,
            path: descriptor.path,
            queryItems: descriptor.queryItems,
            headers: descriptor.headers,
            body: descriptor.body,
            policy: resolvedPolicy
        )
        return StubRoute(
            id: descriptor.id ?? UUID().uuidString,
            matcher: matcher,
            responseProvider: responseProvider
        )
    }

    static func inferredPolicy(
        headers: HTTPHeaders,
        bodyMatchComponent: MatchComponent?
    ) -> MatchingPolicy {
        var components = MatchingPolicy.defaultUIReplay.components
        if !headers.isEmpty, !components.contains(.headerSubset) {
            components.append(.headerSubset)
        }
        if let bodyMatchComponent, !components.contains(bodyMatchComponent) {
            components.append(bodyMatchComponent)
        }
        return MatchingPolicy(components: components)
    }
}
