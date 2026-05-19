import Foundation
import WireStubCore

/// Errors produced while normalizing a HAR archive into a replay scenario.
public enum HARNormalizerError: Error, LocalizedError, Equatable {
    case invalidURL(String, entryIndex: Int)
    case sensitiveDataFound(String, entryIndex: Int)

    /// Human-readable normalization error.
    public var errorDescription: String? {
        switch self {
        case .invalidURL(let url, let index):
            return "HAR entry \(index) has invalid URL: \(url)"
        case .sensitiveDataFound(let field, let index):
            return "HAR entry \(index) contains sensitive data in \(field)"
        }
    }
}

/// Normalizes HAR input material into transport-agnostic `StubScenario` values.
public enum HARNormalizer {
    /// Normalizes a HAR archive into a scenario plus structured warnings.
    public static func normalize(
        _ archive: HARArchive,
        name: String? = nil,
        options: HARImportOptions = .standard
    ) throws -> HARNormalizationResult {
        let routes = try archive.entries.map { try route(from: $0, options: options) }
        let warnings = options.sensitiveHeaderPolicy == .warn
            ? archive.entries.flatMap { sensitiveWarnings(in: $0) }
            : []
        let scenario = StubScenario(
            name: name,
            routes: routes,
            mode: .strict,
            replayStrategy: options.replayStrategy,
            matchingPolicy: options.defaultMatchingPolicy
        )
        return HARNormalizationResult(scenario: scenario, warnings: warnings)
    }

    /// Convenience API that returns only the normalized scenario and discards warnings.
    public static func scenario(
        from archive: HARArchive,
        name: String? = nil,
        options: HARImportOptions = .standard
    ) throws -> StubScenario {
        try normalize(archive, name: name, options: options).scenario
    }

    private static func route(from entry: HAREntry, options: HARImportOptions) throws -> StubRoute {
        guard let components = URLComponents(string: entry.request.url) else {
            throw HARNormalizerError.invalidURL(entry.request.url, entryIndex: entry.index)
        }
        if components.scheme == nil || components.host == nil {
            throw HARNormalizerError.invalidURL(entry.request.url, entryIndex: entry.index)
        }

        if options.sensitiveHeaderPolicy == .fail,
           let sensitive = entry.request.headers.first(where: { harSensitiveHeaderNames.contains($0.name.lowercased()) }) {
            throw HARNormalizerError.sensitiveDataFound(sensitive.name, entryIndex: entry.index)
        }
        if options.sensitiveHeaderPolicy == .fail,
           let sensitive = entry.response.headers.first(where: { harSensitiveHeaderNames.contains($0.name.lowercased()) }) {
            throw HARNormalizerError.sensitiveDataFound(sensitive.name, entryIndex: entry.index)
        }

        var policy = options.defaultMatchingPolicy
        let requestHeaders = HTTPHeaderUtilities.dictionary(from: normalizedRequestHeaders(
            entry.request.headers,
            includeHeaderMatching: options.includeHeaderMatching,
            stripSensitive: options.sensitiveHeaderPolicy == .strip
        ).map { ($0.name, $0.value) })
        if options.includeHeaderMatching && !requestHeaders.isEmpty && !policy.components.contains(.headerSubset) {
            policy.components.append(.headerSubset)
        }

        let queryItems = effectiveQueryItems(for: entry.request).map { QueryItem(name: $0.name, value: $0.value) }
        let path = components.path.isEmpty ? PathUtilities.rootPath : components.path
        let requestBody = entry.request.postData?.text?.data(using: .utf8)
        if let mimeType = entry.request.postData?.mimeType?.lowercased(), mimeType.contains("json"), requestBody != nil {
            if !policy.components.contains(.canonicalJSONBodyHash) && !policy.components.contains(.bodyHash) {
                policy.components.append(.canonicalJSONBodyHash)
            }
        }

        let responseHeaders = HTTPHeaderUtilities.dictionary(from: sanitizedHeaderList(
            entry.response.headers,
            stripSensitive: options.sensitiveHeaderPolicy == .strip,
            stripCookies: options.stripCookies
        ).map { ($0.name, $0.value) })

        let responseBody = try entry.response.decodedBody(decodeBase64Bodies: options.decodeBase64Bodies)
        let route = StubRoute(
            id: "har:entry:\(entry.index)",
            matcher: RouteMatcher(
                method: entry.request.method,
                path: path,
                queryItems: queryItems,
                headers: requestHeaders,
                body: requestBody,
                policy: policy
            ),
            responseProvider: .staticResponse(
                StubResponse(status: entry.response.status, headers: responseHeaders, body: responseBody)
            ),
            metadata: RouteMetadata(sourceFile: "HAR", sourceEntry: entry.index)
        )
        return route
    }
}
