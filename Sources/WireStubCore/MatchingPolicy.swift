import Foundation

// MARK: - MatchComponent

/// Defines which parts of an incoming request are compared against a route.
public enum MatchComponent: Sendable, Equatable, Hashable {
    case method
    case path
    case headerSubset
    /// All query items in the route must be present and equal in the request; extra items are rejected.
    case queryExact
    /// All query items in the route must be present in the request; extra items are allowed.
    case querySubset
    /// Raw SHA-256 of the request body.
    case bodyHash
    /// SHA-256 of the canonical (key-sorted) JSON representation of the request body.
    case canonicalJSONBodyHash
}

// MARK: - MatchingPolicy

/// Defines how incoming requests are compared to routes.
public struct MatchingPolicy: Sendable, Equatable {
    /// Request components evaluated during matching, in order.
    public var components: [MatchComponent]
    /// Headers whose values are excluded from matching (matching by header name is opt-in).
    public var ignoredHeaders: Set<String>
    /// Query item names excluded from matching even when `queryExact` or `querySubset` is active.
    public var ignoredQueryItems: Set<String>

    /// Creates a matching policy.
    public init(
        components: [MatchComponent],
        ignoredHeaders: Set<String> = [],
        ignoredQueryItems: Set<String> = []
    ) {
        self.components = components
        self.ignoredHeaders = Set(ignoredHeaders.map { $0.lowercased() })
        self.ignoredQueryItems = Set(ignoredQueryItems.map { $0.lowercased() })
    }

    /// Default policy for UI test replay:
    /// matches method, path, and query subset; ignores scheme, host, port.
    public static let defaultUIReplay = MatchingPolicy(
        components: [.method, .path, .querySubset]
    )
}
