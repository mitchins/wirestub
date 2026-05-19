import Foundation
import WireStubCore

/// Body matching mode used by XCTest request expectations.
public enum RequestBodyMatching: Sendable, Equatable {
    /// Match the raw request body bytes exactly.
    case exactBytes
    /// Match the request body by canonical JSON hash, falling back deterministically to raw bytes.
    case canonicalJSON
}

/// A request expectation used by XCTest assertion helpers.
public struct RequestExpectation: Sendable, Equatable, CustomStringConvertible {
    /// Expected HTTP method.
    public let method: String
    /// Expected request path.
    public let path: String
    /// Expected query items. All items must be present; extra request query items are allowed.
    public let queryItems: [QueryItem]
    /// Expected request headers. All items must be present with equal values.
    public let headers: HTTPHeaders
    /// Expected request body, if any.
    public let body: Data?
    /// Body matching mode when `body` is present.
    public let bodyMatching: RequestBodyMatching?

    /// Creates a request expectation.
    public init(
        method: String,
        path: String,
        queryItems: [QueryItem] = [],
        headers: HTTPHeaders = [:],
        body: Data? = nil,
        bodyMatching: RequestBodyMatching? = nil
    ) {
        self.method = method.uppercased()
        self.path = path
        self.queryItems = queryItems
        self.headers = headers
        self.body = body
        self.bodyMatching = body == nil ? nil : (bodyMatching ?? .exactBytes)
    }

    /// Creates a GET expectation.
    public static func get(
        _ path: String,
        queryItems: [QueryItem] = [],
        headers: HTTPHeaders = [:]
    ) -> RequestExpectation {
        .init(method: "GET", path: path, queryItems: queryItems, headers: headers)
    }

    /// Creates a POST expectation.
    public static func post(
        _ path: String,
        queryItems: [QueryItem] = [],
        headers: HTTPHeaders = [:],
        body: Data? = nil
    ) -> RequestExpectation {
        .init(method: "POST", path: path, queryItems: queryItems, headers: headers, body: body)
    }

    /// Creates a POST expectation with canonical-JSON body matching.
    public static func post<Body: Encodable>(
        _ path: String,
        queryItems: [QueryItem] = [],
        headers: HTTPHeaders = [:],
        jsonBody: Body,
        encoder: JSONEncoder = JSONEncoder()
    ) throws -> RequestExpectation {
        try .init(
            method: "POST",
            path: path,
            queryItems: queryItems,
            headers: headers,
            body: encoder.encode(jsonBody),
            bodyMatching: .canonicalJSON
        )
    }

    /// Creates a PUT expectation.
    public static func put(
        _ path: String,
        queryItems: [QueryItem] = [],
        headers: HTTPHeaders = [:],
        body: Data? = nil
    ) -> RequestExpectation {
        .init(method: "PUT", path: path, queryItems: queryItems, headers: headers, body: body)
    }

    /// Creates a PUT expectation with canonical-JSON body matching.
    public static func put<Body: Encodable>(
        _ path: String,
        queryItems: [QueryItem] = [],
        headers: HTTPHeaders = [:],
        jsonBody: Body,
        encoder: JSONEncoder = JSONEncoder()
    ) throws -> RequestExpectation {
        try .init(
            method: "PUT",
            path: path,
            queryItems: queryItems,
            headers: headers,
            body: encoder.encode(jsonBody),
            bodyMatching: .canonicalJSON
        )
    }

    /// Creates a PATCH expectation.
    public static func patch(
        _ path: String,
        queryItems: [QueryItem] = [],
        headers: HTTPHeaders = [:],
        body: Data? = nil
    ) -> RequestExpectation {
        .init(method: "PATCH", path: path, queryItems: queryItems, headers: headers, body: body)
    }

    /// Creates a PATCH expectation with canonical-JSON body matching.
    public static func patch<Body: Encodable>(
        _ path: String,
        queryItems: [QueryItem] = [],
        headers: HTTPHeaders = [:],
        jsonBody: Body,
        encoder: JSONEncoder = JSONEncoder()
    ) throws -> RequestExpectation {
        try .init(
            method: "PATCH",
            path: path,
            queryItems: queryItems,
            headers: headers,
            body: encoder.encode(jsonBody),
            bodyMatching: .canonicalJSON
        )
    }

    /// Creates a DELETE expectation.
    public static func delete(
        _ path: String,
        queryItems: [QueryItem] = [],
        headers: HTTPHeaders = [:]
    ) -> RequestExpectation {
        .init(method: "DELETE", path: path, queryItems: queryItems, headers: headers)
    }

    /// Returns whether the expectation matches a recorded request snapshot.
    public func matches(_ request: RequestSnapshot) -> Bool {
        guard method == request.method.uppercased(), path == request.path else {
            return false
        }

        var remainingQueryItems = request.queryItems
        for item in queryItems {
            guard let index = remainingQueryItems.firstIndex(of: item) else {
                return false
            }
            remainingQueryItems.remove(at: index)
        }

        for (name, expectedValue) in headers {
            guard HTTPHeaderUtilities.value(named: name, in: request.headers) == expectedValue else {
                return false
            }
        }

        guard let bodyMatching else {
            return body == nil
        }

        switch bodyMatching {
        case .exactBytes:
            return body == request.body
        case .canonicalJSON:
            let expectedHash = BodyCanonicalizer.canonicalJSONHash(body ?? Data(), fallbackSide: .route).hash
            let receivedHash = BodyCanonicalizer.canonicalJSONHash(request.body ?? Data(), fallbackSide: .request).hash
            return expectedHash == receivedHash
        }
    }

    /// Human-readable expectation used in assertion messages.
    public var description: String {
        let renderedTarget = RequestSnapshot(method: method, path: path, queryItems: queryItems).renderedTarget(redacted: true)
        var details: [String] = []
        if !headers.isEmpty {
            details.append("headers: \(headers.keys.sorted().joined(separator: ", "))")
        }
        if let bodyMatching {
            switch bodyMatching {
            case .exactBytes:
                details.append("body")
            case .canonicalJSON:
                details.append("json body")
            }
        }
        guard !details.isEmpty else {
            return renderedTarget
        }
        return "\(renderedTarget) [\(details.joined(separator: "; "))]"
    }
}
