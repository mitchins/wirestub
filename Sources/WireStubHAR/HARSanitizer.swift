import Foundation

/// Sanitizes HAR archives by removing sensitive headers and redacting sensitive query/JSON values.
///
/// Sanitization preserves request and response structure so the resulting HAR can still be loaded and normalized.
/// Sensitive field names remain in place by default, so validation may still report that a HAR contains sensitive keys,
/// but rendered diagnostics and serialized output will not include the original secret values.
public enum HARSanitizer {
    /// Placeholder inserted when a sensitive value is redacted.
    public static let redactedPlaceholder = "[REDACTED]"

    /// Sanitizes a HAR archive using the default redaction policy and returns the sanitized archive only.
    public static func sanitize(_ archive: HARArchive) -> HARArchive {
        sanitize(archive, options: .standard).archive
    }

    /// Sanitizes a HAR archive and returns both the sanitized archive and a summary of the applied changes.
    public static func sanitize(
        _ archive: HARArchive,
        options: HARSanitizationOptions
    ) -> HARSanitizationResult {
        var summary = HARSanitizationSummary()
        let entries = archive.entries.map { sanitize($0, options: options, summary: &summary) }
        return HARSanitizationResult(archive: HARArchive(entries: entries), summary: summary)
    }

    /// Serializes a HAR archive back into a loadable HAR document.
    public static func data(from archive: HARArchive) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(HARDocumentEnvelope(log: HARLogEnvelope(entries: archive.entries.map(EncodedHAREntry.init))))
    }

    private static func sanitize(
        _ entry: HAREntry,
        options: HARSanitizationOptions,
        summary: inout HARSanitizationSummary
    ) -> HAREntry {
        var request = entry.request
        let sanitizedRequestHeaders = request.headers.filter { !options.removeHeaders.contains($0.name.lowercased()) }
        summary.removedRequestHeaders += request.headers.count - sanitizedRequestHeaders.count
        request.headers = sanitizedRequestHeaders

        let sanitizedQuery = sanitizedQueryItems(from: request, options: options, summary: &summary)
        request.queryString = sanitizedQuery
        request.url = sanitizedURLString(from: request.url, queryItems: sanitizedQuery)

        if let postData = request.postData {
            let redactedRequestJSON = redactJSON(postData.text, redactKeys: options.redactJSONKeys)
            summary.redactedJSONValues += redactedRequestJSON.count
            request.postData = HARPostData(mimeType: postData.mimeType, text: redactedRequestJSON.text)
        }

        var response = entry.response
        let sanitizedResponseHeaders = response.headers.filter { !options.removeHeaders.contains($0.name.lowercased()) }
        summary.removedResponseHeaders += response.headers.count - sanitizedResponseHeaders.count
        response.headers = sanitizedResponseHeaders

        response.content = redactedContent(
            response.content,
            redactKeys: options.redactJSONKeys,
            summary: &summary
        )
        return HAREntry(index: entry.index, request: request, response: response)
    }

    private static func sanitizedQueryItems(
        from request: HARRequest,
        options: HARSanitizationOptions,
        summary: inout HARSanitizationSummary
    ) -> [HARNameValue] {
        let items: [HARNameValue]
        if request.queryString.isEmpty {
            items = queryItems(from: request.url)
        } else {
            items = request.queryString
        }

        return items.map { item in
            if options.redactQueryItems.contains(item.name.lowercased()) {
                summary.redactedQueryItems += 1
                return HARNameValue(name: item.name, value: redactedPlaceholder)
            }
            return item
        }
    }

    private static func redactJSON(_ text: String?, redactKeys: Set<String>) -> (text: String?, count: Int) {
        guard let text, let data = text.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) else {
            return (text, 0)
        }
        let redacted = redactJSONValue(object, redactKeys: redactKeys)
        guard let out = try? JSONSerialization.data(withJSONObject: redacted.json, options: [.sortedKeys]) else {
            return (text, 0)
        }
        return (String(decoding: out, as: UTF8.self), redacted.redactionCount)
    }

    private static func redactedContent(
        _ content: HARContent,
        redactKeys: Set<String>,
        summary: inout HARSanitizationSummary
    ) -> HARContent {
        guard let text = content.text else { return content }

        if content.encoding?.lowercased() == "base64",
           let data = Data(base64Encoded: text),
           let redacted = redactJSON(data, redactKeys: redactKeys) {
            summary.redactedJSONValues += redacted.count
            return HARContent(
                mimeType: content.mimeType,
                text: redacted.data.base64EncodedString(),
                encoding: content.encoding
            )
        }

        let redacted = redactJSON(text, redactKeys: redactKeys)
        summary.redactedJSONValues += redacted.count
        return HARContent(mimeType: content.mimeType, text: redacted.text, encoding: content.encoding)
    }

    private static func redactJSON(_ data: Data, redactKeys: Set<String>) -> (data: Data, count: Int)? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        let redacted = redactJSONValue(object, redactKeys: redactKeys)
        guard let out = try? JSONSerialization.data(withJSONObject: redacted.json, options: [.sortedKeys]) else {
            return nil
        }
        return (out, redacted.redactionCount)
    }

    private static func sanitizedURLString(from original: String, queryItems: [HARNameValue]) -> String {
        guard var components = URLComponents(string: original) else { return original }
        components.queryItems = queryItems.isEmpty ? nil : queryItems.map { URLQueryItem(name: $0.name, value: $0.value) }
        return components.string ?? original
    }

    private static func queryItems(from urlString: String) -> [HARNameValue] {
        guard let components = URLComponents(string: urlString) else { return [] }
        return (components.queryItems ?? []).map { HARNameValue(name: $0.name, value: $0.value ?? "") }
    }

    private static func redactJSONValue(_ value: Any, redactKeys: Set<String>) -> (json: Any, redactionCount: Int) {
        if let dict = value as? [String: Any] {
            var output: [String: Any] = [:]
            var count = 0
            for (key, nested) in dict {
                if redactKeys.contains(key.lowercased()) {
                    output[key] = redactedPlaceholder
                    count += 1
                } else {
                    let redactedNested = redactJSONValue(nested, redactKeys: redactKeys)
                    output[key] = redactedNested.json
                    count += redactedNested.redactionCount
                }
            }
            return (output, count)
        }
        if let array = value as? [Any] {
            let redacted = array.map { redactJSONValue($0, redactKeys: redactKeys) }
            return (redacted.map(\.json), redacted.reduce(into: 0) { $0 += $1.redactionCount })
        }
        return (value, 0)
    }
}

private struct HARDocumentEnvelope: Encodable {
    var log: HARLogEnvelope
}

private struct HARLogEnvelope: Encodable {
    var entries: [EncodedHAREntry]
}

private struct EncodedHAREntry: Encodable {
    var request: HARRequest
    var response: HARResponse

    init(_ entry: HAREntry) {
        self.request = entry.request
        self.response = entry.response
    }
}
