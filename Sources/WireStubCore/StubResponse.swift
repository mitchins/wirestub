import Foundation

// MARK: - StubResponse

/// A transport-agnostic HTTP response to be returned by the replay engine.
public struct StubResponse: Sendable, Equatable {
    /// HTTP status code returned to the caller.
    public var status: Int
    /// Response headers returned to the caller.
    public var headers: HTTPHeaders
    /// Raw response body bytes.
    public var body: Data
    /// Optional artificial delay applied by transport adapters before delivering the response.
    public var delay: Duration?

    /// Creates a stubbed HTTP response.
    public init(
        status: Int,
        headers: HTTPHeaders = [:],
        body: Data = Data(),
        delay: Duration? = nil
    ) {
        self.status = status
        self.headers = headers
        self.body = body
        self.delay = delay
    }
}

// MARK: - Convenience builders

/// Convenience builders for common HTTP response shapes.
public extension StubResponse {
    /// Builds a JSON response by encoding an `Encodable` value.
    static func json(
        _ encodable: some Encodable,
        status: Int = 200,
        headers: HTTPHeaders = [:],
        delay: Duration? = nil,
        encoder: JSONEncoder = JSONEncoder()
    ) throws -> StubResponse {
        let body = try encoder.encode(encodable)
        var merged = headers
        merged["Content-Type"] = "application/json"
        return StubResponse(status: status, headers: merged, body: body, delay: delay)
    }

    /// Builds a JSON response from a Foundation JSON object.
    static func json(
        _ value: Any,
        status: Int = 200,
        headers: HTTPHeaders = [:],
        delay: Duration? = nil
    ) throws -> StubResponse {
        let body = try JSONSerialization.data(withJSONObject: value)
        var merged = headers
        merged["Content-Type"] = "application/json"
        return StubResponse(status: status, headers: merged, body: body, delay: delay)
    }

    /// Builds a plain-text response.
    static func text(
        _ string: String,
        status: Int = 200,
        headers: HTTPHeaders = [:],
        delay: Duration? = nil,
        encoding: String.Encoding = .utf8
    ) -> StubResponse {
        let body = string.data(using: encoding) ?? Data()
        var merged = headers
        let charset = StubResponse.contentTypeCharset(for: encoding)
        merged["Content-Type"] = "text/plain; charset=\(charset)"
        return StubResponse(status: status, headers: merged, body: body, delay: delay)
    }

    /// Builds an empty-body response with only status and headers.
    static func status(
        _ code: Int,
        headers: HTTPHeaders = [:],
        delay: Duration? = nil
    ) -> StubResponse {
        StubResponse(status: code, headers: headers, body: Data(), delay: delay)
    }

    /// Builds a binary response with a configurable content type.
    static func data(
        _ body: Data,
        contentType: String = "application/octet-stream",
        status: Int = 200,
        headers: HTTPHeaders = [:],
        delay: Duration? = nil
    ) -> StubResponse {
        var merged = headers
        merged["Content-Type"] = contentType
        return StubResponse(status: status, headers: merged, body: body, delay: delay)
    }

    private static func contentTypeCharset(for encoding: String.Encoding) -> String {
        let cfEncoding = CFStringConvertNSStringEncodingToEncoding(encoding.rawValue)
        let charset = CFStringConvertEncodingToIANACharSetName(cfEncoding).map { $0 as String }
        return charset ?? "utf-8"
    }
}
