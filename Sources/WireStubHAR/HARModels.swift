import Foundation
import WireStubCore

/// Decoded HAR document used as input material for normalization and tooling.
public struct HARArchive: Sendable, Equatable, Codable {
    /// Entries contained in the HAR log.
    public var entries: [HAREntry]

    /// Creates a HAR archive.
    public init(entries: [HAREntry]) {
        self.entries = entries
    }
}

/// A single HAR log entry.
public struct HAREntry: Sendable, Equatable, Codable {
    /// Zero-based entry index assigned during loading.
    public var index: Int
    /// HAR request payload.
    public var request: HARRequest
    /// HAR response payload.
    public var response: HARResponse

    /// Creates a HAR entry.
    public init(index: Int, request: HARRequest, response: HARResponse) {
        self.index = index
        self.request = request
        self.response = response
    }
}

/// HAR request model used for input parsing and sanitization.
public struct HARRequest: Sendable, Equatable, Codable {
    /// HTTP method.
    public var method: String
    /// Request URL.
    public var url: String
    /// Request headers.
    public var headers: [HARNameValue]
    /// Request query items.
    public var queryString: [HARNameValue]
    /// Optional request body metadata.
    public var postData: HARPostData?

    /// Creates a HAR request.
    public init(method: String, url: String, headers: [HARNameValue] = [], queryString: [HARNameValue] = [], postData: HARPostData? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.queryString = queryString
        self.postData = postData
    }
}

/// HAR response model used for input parsing and sanitization.
public struct HARResponse: Sendable, Equatable, Codable {
    /// HTTP status code.
    public var status: Int
    /// Response headers.
    public var headers: [HARNameValue]
    /// Response body metadata.
    public var content: HARContent

    /// Creates a HAR response.
    public init(status: Int, headers: [HARNameValue] = [], content: HARContent) {
        self.status = status
        self.headers = headers
        self.content = content
    }

    /// Decodes the response body, optionally treating `encoding == base64` as binary data.
    public func decodedBody(decodeBase64Bodies: Bool) throws -> Data {
        try content.decodedBody(decodeBase64Bodies: decodeBase64Bodies)
    }
}

/// HAR response content metadata.
public struct HARContent: Sendable, Equatable, Codable {
    /// Content MIME type, if present.
    public var mimeType: String?
    /// Raw text payload.
    public var text: String?
    /// Content encoding, such as `base64`.
    public var encoding: String?

    /// Creates HAR content metadata.
    public init(mimeType: String? = nil, text: String? = nil, encoding: String? = nil) {
        self.mimeType = mimeType
        self.text = text
        self.encoding = encoding
    }

    /// Decodes this HAR content into body bytes.
    public func decodedBody(decodeBase64Bodies: Bool) throws -> Data {
        guard let text else { return Data() }
        if decodeBase64Bodies, encoding?.lowercased() == "base64" {
            guard let data = Data(base64Encoded: text) else {
                throw HARLoaderError.invalidBase64Body
            }
            return data
        }
        return Data(text.utf8)
    }
}

/// Generic HAR name/value pair.
public struct HARNameValue: Sendable, Equatable, Codable {
    /// Field name.
    public var name: String
    /// Field value.
    public var value: String

    /// Creates a HAR name/value pair.
    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

/// HAR request body metadata.
public struct HARPostData: Sendable, Equatable, Codable {
    /// Request body MIME type, if present.
    public var mimeType: String?
    /// Request body text payload.
    public var text: String?

    /// Creates HAR post data metadata.
    public init(mimeType: String? = nil, text: String? = nil) {
        self.mimeType = mimeType
        self.text = text
    }
}

/// Structured normalization or validation warning that does not expose secret values.
public struct HARValidationWarning: Sendable, Equatable, Codable {
    /// Entry index that produced the warning.
    public var entryIndex: Int
    /// Human-readable warning message.
    public var message: String

    /// Creates a structured validation warning.
    public init(entryIndex: Int, message: String) {
        self.entryIndex = entryIndex
        self.message = message
    }
}

/// Result of normalizing a HAR archive into a replay scenario.
public struct HARNormalizationResult: Sendable {
    /// Normalized replay scenario.
    public var scenario: StubScenario
    /// Structured warnings produced during normalization.
    public var warnings: [HARValidationWarning]

    /// Creates a normalization result.
    public init(scenario: StubScenario, warnings: [HARValidationWarning]) {
        self.scenario = scenario
        self.warnings = warnings
    }
}

/// Options controlling how HAR sanitization removes or redacts sensitive data.
public struct HARSanitizationOptions: Sendable, Equatable {
    /// Header names to remove entirely from sanitized output.
    public var removeHeaders: Set<String>
    /// Query item names whose values should be replaced with the redacted placeholder.
    public var redactQueryItems: Set<String>
    /// JSON key names whose values should be replaced with the redacted placeholder.
    public var redactJSONKeys: Set<String>

    /// Creates HAR sanitization options.
    public init(
        removeHeaders: Set<String>? = nil,
        redactQueryItems: Set<String>? = nil,
        redactJSONKeys: Set<String>? = nil
    ) {
        self.removeHeaders = Set((removeHeaders ?? harSensitiveHeaderNames).map { $0.lowercased() })
        self.redactQueryItems = Set((redactQueryItems ?? harSensitiveQueryNames).map { $0.lowercased() })
        self.redactJSONKeys = Set((redactJSONKeys ?? harSensitiveJSONKeys).map { $0.lowercased() })
    }

    /// Default sanitization policy for CLI and library use.
    ///
    /// Defaults remove sensitive headers and redact sensitive query/JSON values while preserving key names.
    /// Validation may still warn on those preserved names, but never on the original values.
    public static let standard = HARSanitizationOptions()
}

/// Aggregate counts of sanitization operations.
public struct HARSanitizationSummary: Sendable, Equatable {
    /// Number of request headers removed.
    public var removedRequestHeaders: Int
    /// Number of response headers removed.
    public var removedResponseHeaders: Int
    /// Number of query values redacted.
    public var redactedQueryItems: Int
    /// Number of JSON values redacted.
    public var redactedJSONValues: Int

    /// Creates a sanitization summary.
    public init(
        removedRequestHeaders: Int = 0,
        removedResponseHeaders: Int = 0,
        redactedQueryItems: Int = 0,
        redactedJSONValues: Int = 0
    ) {
        self.removedRequestHeaders = removedRequestHeaders
        self.removedResponseHeaders = removedResponseHeaders
        self.redactedQueryItems = redactedQueryItems
        self.redactedJSONValues = redactedJSONValues
    }
}

/// Result of sanitizing a HAR archive.
public struct HARSanitizationResult: Sendable, Equatable {
    /// Sanitized HAR archive.
    public var archive: HARArchive
    /// Aggregate counts of redactions and removals applied during sanitization.
    public var summary: HARSanitizationSummary

    /// Creates a sanitization result.
    public init(archive: HARArchive, summary: HARSanitizationSummary) {
        self.archive = archive
        self.summary = summary
    }
}

/// Controls how normalization responds to sensitive headers found in input HAR files.
public enum SensitiveHeaderPolicy: Sendable, Equatable {
    case warn
    case strip
    case fail
}

/// Options controlling HAR normalization into a `StubScenario`.
public struct HARImportOptions: Sendable, Equatable {
    /// Default matching policy inherited by normalized routes.
    public var defaultMatchingPolicy: MatchingPolicy
    /// Replay strategy used by the normalized scenario.
    public var replayStrategy: ReplayStrategy
    /// Behavior when sensitive headers are present in the HAR.
    public var sensitiveHeaderPolicy: SensitiveHeaderPolicy
    /// Whether base64 response bodies should be decoded to binary data.
    public var decodeBase64Bodies: Bool
    /// Whether `Set-Cookie` headers should be stripped from normalized responses.
    public var stripCookies: Bool
    /// Whether request header matching should be enabled during normalization.
    public var includeHeaderMatching: Bool

    /// Creates HAR normalization options.
    public init(
        defaultMatchingPolicy: MatchingPolicy = .defaultUIReplay,
        replayStrategy: ReplayStrategy = .ordered,
        sensitiveHeaderPolicy: SensitiveHeaderPolicy = .warn,
        decodeBase64Bodies: Bool = true,
        stripCookies: Bool = false,
        includeHeaderMatching: Bool = false
    ) {
        self.defaultMatchingPolicy = defaultMatchingPolicy
        self.replayStrategy = replayStrategy
        self.sensitiveHeaderPolicy = sensitiveHeaderPolicy
        self.decodeBase64Bodies = decodeBase64Bodies
        self.stripCookies = stripCookies
        self.includeHeaderMatching = includeHeaderMatching
    }

    /// Default HAR import options tuned for UI replay.
    public static let standard = HARImportOptions()
}
