import Foundation

// MARK: - Sensitive key sets

private let sensitiveHeaderNames: Set<String> = [
    "authorization", "cookie", "set-cookie", "x-api-key",
]

private let sensitiveQueryNames: Set<String> = [
    "token", "api_key", "access_token", "refresh_token", "password",
]

// MARK: - Redactor

/// Redaction helpers shared by diagnostics, journals, and assertion output.
public enum Redactor {
    /// Placeholder used when sensitive values are redacted.
    public static let redactedPlaceholder = "[REDACTED]"

    /// Pass-through header redaction hook for future customization.
    public static func redact(headers: HTTPHeaders) -> HTTPHeaders {
        headers.mapValues { value in
            // We check by key in the callsite; this is a passthrough.
            value
        }
    }

    /// Returns headers with sensitive values replaced by [REDACTED].
    public static func redactSensitive(headers: HTTPHeaders) -> HTTPHeaders {
        Dictionary(uniqueKeysWithValues: headers.map { key, value in
            (key, sensitiveHeaderNames.contains(key.lowercased()) ? redactedPlaceholder : value)
        })
    }

    /// Returns query items with sensitive values replaced by [REDACTED].
    public static func redactSensitive(queryItems: [QueryItem]) -> [QueryItem] {
        queryItems.map { item in
            sensitiveQueryNames.contains(item.name.lowercased())
                ? QueryItem(name: item.name, value: redactedPlaceholder)
                : item
        }
    }

    /// Returns whether a header name is treated as sensitive for rendering.
    public static func isSensitiveHeader(_ name: String) -> Bool {
        sensitiveHeaderNames.contains(name.lowercased())
    }

    /// Returns whether a query item name is treated as sensitive for rendering.
    public static func isSensitiveQueryItem(_ name: String) -> Bool {
        sensitiveQueryNames.contains(name.lowercased())
    }
}

/// Redacted or raw rendering helpers for request snapshots.
public extension RequestSnapshot {
    /// Renders the request target as `METHOD /path?...`, optionally redacting sensitive query values.
    func renderedTarget(redacted: Bool = true) -> String {
        let renderedQueryItems = redacted ? Redactor.redactSensitive(queryItems: queryItems) : queryItems
        guard !renderedQueryItems.isEmpty else {
            return "\(method) \(path)"
        }

        let queryString = renderedQueryItems.map { item in
            if let value = item.value {
                return "\(item.name)=\(value)"
            }
            return item.name
        }.joined(separator: "&")
        return "\(method) \(path)?\(queryString)"
    }
}

/// Redacted or raw rendering helpers for journal entries.
public extension JournalEntry {
    /// Renders a timeline line for a journal entry.
    func renderedTimelineLine(redacted: Bool = true) -> String {
        let outcomeStr: String
        switch outcome {
        case .matched(let id, let status):
            outcomeStr = "-> \(status) (route: \(id))"
        case .unmatched:
            outcomeStr = "-> unmatched"
        }
        return "\(sequenceIndex + 1). \(request.renderedTarget(redacted: redacted)) \(outcomeStr)"
    }
}

/// Redacted or raw rendering helpers for request journals.
public extension RequestJournal {
    /// Renders the full request timeline.
    func renderedTimeline(redacted: Bool = true) -> String {
        guard !entries.isEmpty else {
            return "<empty>"
        }
        return entries.map { $0.renderedTimelineLine(redacted: redacted) }.joined(separator: "\n")
    }
}

// MARK: - UnmatchedRequestDiagnostic

/// Structured unmatched-request diagnostic produced by the replay engine.
public struct UnmatchedRequestDiagnostic: Sendable {
    /// Request that could not be matched.
    public let request: RequestSnapshot
    /// Scenario name, if supplied.
    public let scenarioName: String?
    /// Replay strategy active when the request was handled.
    public let replayStrategy: ReplayStrategy
    /// Closest route evaluations, sorted by mismatch count.
    public let closestCandidates: [MatchEvaluation]
    /// Next expected route identifier for ordered replay, if any.
    public let nextExpectedRouteID: String?
    /// Requests already recorded in the journal at the time of failure.
    public let requestsReceivedSoFar: [JournalEntry]

    /// Human-readable diagnostic, with sensitive values redacted.
    public func render() -> String {
        var lines: [String] = []
        let redactedHeaders = Redactor.redactSensitive(headers: request.headers)
        let redactedQuery = Redactor.redactSensitive(queryItems: request.queryItems)

        lines.append("No matching WireStub route for \(request.method) \(request.path)")
        lines.append("")
        if let name = scenarioName {
            lines.append("Scenario: \(name)")
        }
        lines.append("Replay strategy: \(replayStrategy)")
        lines.append("")
        lines.append("Request headers (redacted):")
        for (key, val) in redactedHeaders.sorted(by: { $0.key < $1.key }) {
            lines.append("  \(key): \(val)")
        }
        if !redactedQuery.isEmpty {
            lines.append("Query items:")
            for item in redactedQuery {
                lines.append("  \(item.name)=\(item.value ?? "")")
            }
        }
        lines.append("")
        if let nextID = nextExpectedRouteID {
            lines.append("Expected next route: \(nextID)")
        }
        if !closestCandidates.isEmpty {
            lines.append("Closest candidates:")
            for candidate in closestCandidates.prefix(3) {
                lines.append("  Route \(candidate.routeID):")
                for reason in candidate.reasons.prefix(3) {
                    lines.append("    - \(reason.renderedDescription(redacted: true))")
                }
            }
        }
        lines.append("")
        lines.append("Requests received so far:")
        for entry in requestsReceivedSoFar {
            lines.append("  \(entry.renderedTimelineLine(redacted: true))")
        }
        return lines.joined(separator: "\n")
    }
}
