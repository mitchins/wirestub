import Foundation

// MARK: - Primitive types

/// Normalized HTTP method string used by the replay engine.
public typealias HTTPMethod = String
/// Normalized HTTP header map used by the replay engine.
public typealias HTTPHeaders = [String: String]

/// Helpers for duplicate-safe and case-insensitive header normalization.
public enum HTTPHeaderUtilities {
    /// Builds a deterministic header dictionary from potentially duplicated header pairs.
    public static func dictionary<S: Sequence>(
        from pairs: S
    ) -> HTTPHeaders where S.Element == (String, String) {
        var canonicalNames: [String: String] = [:]
        var valuesByName: [String: [String]] = [:]
        var orderedNames: [String] = []

        for (name, value) in pairs {
            let lowered = name.lowercased()
            if canonicalNames[lowered] == nil {
                canonicalNames[lowered] = name
                orderedNames.append(lowered)
            }
            valuesByName[lowered, default: []].append(value)
        }

        var output: HTTPHeaders = [:]
        for lowered in orderedNames {
            guard let canonicalName = canonicalNames[lowered] else { continue }
            output[canonicalName] = valuesByName[lowered, default: []].joined(separator: ", ")
        }
        return output
    }

    /// Returns a header value using case-insensitive lookup.
    public static func value(named name: String, in headers: HTTPHeaders) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

/// A single query item captured from a request URL.
public struct QueryItem: Sendable, Equatable, Hashable {
    /// Query item name.
    public var name: String
    /// Query item value, if present.
    public var value: String?

    /// Creates a query item.
    public init(name: String, value: String? = nil) {
        self.name = name
        self.value = value
    }
}

/// Target metadata associated with a request snapshot.
public struct RequestTarget: Sendable, Equatable {
    /// Request scheme, if available.
    public var scheme: String?
    /// Request host, if available.
    public var host: String?
    /// Request port, if available.
    public var port: Int?

    /// Creates a request target.
    public init(scheme: String? = nil, host: String? = nil, port: Int? = nil) {
        self.scheme = scheme
        self.host = host
        self.port = port
    }
}

// MARK: - RequestSnapshot

/// A transport-agnostic snapshot of an inbound HTTP request.
public struct RequestSnapshot: Sendable, Equatable {
    /// Normalized HTTP method.
    public var method: HTTPMethod
    /// Request scheme, if available.
    public var scheme: String?
    /// Request host, if available.
    public var host: String?
    /// Request port, if available.
    public var port: Int?
    /// Request path component.
    public var path: String
    /// Ordered query items, preserving duplicates.
    public var queryItems: [QueryItem]
    /// Normalized request headers.
    public var headers: HTTPHeaders
    /// Raw request body bytes, if available.
    public var body: Data?
    /// Adapter-supplied receive timestamp, if available.
    public var receivedAt: Date?

    /// Creates a transport-agnostic request snapshot.
    public init(
        method: HTTPMethod,
        path: String,
        target: RequestTarget = RequestTarget(),
        queryItems: [QueryItem] = [],
        headers: HTTPHeaders = [:],
        body: Data? = nil,
        receivedAt: Date? = nil
    ) {
        self.method = method.uppercased()
        self.scheme = target.scheme
        self.host = target.host
        self.port = target.port
        self.path = path
        self.queryItems = queryItems
        self.headers = headers
        self.body = body
        self.receivedAt = receivedAt
    }

    /// Convenience initializer for requests without target metadata.
    public init(
        method: HTTPMethod,
        path: String,
        queryItems: [QueryItem] = [],
        headers: HTTPHeaders = [:],
        body: Data? = nil,
        receivedAt: Date? = nil
    ) {
        self.init(
            method: method,
            path: path,
            target: RequestTarget(),
            queryItems: queryItems,
            headers: headers,
            body: body,
            receivedAt: receivedAt
        )
    }
}
