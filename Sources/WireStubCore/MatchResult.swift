import Foundation

// MARK: - MismatchReason

/// A structured, explainable reason why a route did not match a request.
public enum MismatchReason: Sendable, Equatable, CustomStringConvertible {
    case methodMismatch(expected: String, received: String)
    case pathMismatch(expected: String, received: String)
    case headerMismatch(name: String, expected: String, received: String?)
    case missingQueryItem(name: String, expectedValue: String?)
    case extraQueryItem(name: String)
    case bodyHashMismatch(expected: String, received: String)
    case canonicalJSONBodyHashMismatch(expected: String, received: String)
    /// Raised when JSON canonicalization failed on the route side, the request side, or both.
    case canonicalizationFailed(side: CanonicalFailureSide, underlying: String)
    case sequenceExhausted(routeID: String)
    case cursorMismatch(expectedRouteID: String, receivedPath: String)

    /// Unredacted human-readable description.
    public var description: String {
        renderedDescription(redacted: false)
    }

    /// Human-readable description with optional secret redaction.
    public func renderedDescription(redacted: Bool) -> String {
        switch self {
        case .methodMismatch(let exp, let rec):
            return "method mismatch: expected \(exp), got \(rec)"
        case .pathMismatch(let exp, let rec):
            return "path mismatch: expected \(exp), got \(rec)"
        case .headerMismatch(let name, let expected, let received):
            let renderedExpected = redacted && Redactor.isSensitiveHeader(name) ? Redactor.redactedPlaceholder : expected
            let renderedReceived = if let received {
                redacted && Redactor.isSensitiveHeader(name) ? Redactor.redactedPlaceholder : received
            } else {
                "<missing>"
            }
            return "header mismatch for \(name): expected \(renderedExpected), got \(renderedReceived)"
        case .missingQueryItem(let name, let value):
            if let value {
                let renderedValue = redacted && Redactor.isSensitiveQueryItem(name) ? Redactor.redactedPlaceholder : value
                return "missing query item \(name)=\(renderedValue)"
            }
            return "missing query item \(name)"
        case .extraQueryItem(let name):
            return "extra query item not in route: \(name)"
        case .bodyHashMismatch(let exp, let rec):
            return "body hash mismatch: expected \(exp), got \(rec)"
        case .canonicalJSONBodyHashMismatch(let exp, let rec):
            return "canonical JSON body hash mismatch: expected \(exp), got \(rec)"
        case .canonicalizationFailed(let side, let reason):
            return "JSON canonicalization failed on \(side): \(reason); fell back to raw body hash"
        case .sequenceExhausted(let id):
            return "response sequence for route \(id) is exhausted"
        case .cursorMismatch(let expected, let received):
            return "ordered replay expected route \(expected), got request for \(received)"
        }
    }
}

/// Indicates which side failed canonical JSON processing.
public enum CanonicalFailureSide: Sendable, Equatable, CustomStringConvertible {
    case route, request, both
    /// Human-readable description of the failing side.
    public var description: String {
        switch self {
        case .route: return "route"
        case .request: return "request"
        case .both: return "route and request"
        }
    }
}

// MARK: - MatchEvaluation

/// The explainable result of evaluating a route against a request.
public struct MatchEvaluation: Sendable {
    /// Route identifier that was evaluated.
    public let routeID: String
    /// Whether the route matched successfully.
    public let isMatch: Bool
    /// Structured mismatch reasons when `isMatch` is false.
    public let reasons: [MismatchReason]

    /// Creates a successful evaluation.
    public static func match(routeID: String) -> MatchEvaluation {
        MatchEvaluation(routeID: routeID, isMatch: true, reasons: [])
    }

    /// Creates a failed evaluation with reasons.
    public static func mismatch(routeID: String, reasons: [MismatchReason]) -> MatchEvaluation {
        MatchEvaluation(routeID: routeID, isMatch: false, reasons: reasons)
    }
}
