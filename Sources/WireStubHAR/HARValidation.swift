import Foundation
import WireStubCore

let harSensitiveHeaderNames: Set<String> = ["authorization", "cookie", "set-cookie", "x-api-key"]
let harSensitiveQueryNames: Set<String> = ["token", "api_key", "access_token", "refresh_token", "password"]
let harSensitiveJSONKeys: Set<String> = ["token", "api_key", "access_token", "refresh_token", "password"]
let volatileRequestHeaderNames: Set<String> = ["accept-encoding", "connection", "content-length", "host", "user-agent"]

/// Human-readable validation report for a HAR archive.
public struct HARValidationReport: Sendable, Equatable {
    /// Number of entries seen in the archive.
    public var entryCount: Int
    /// Request method/path summaries for each entry.
    public var methodsAndPaths: [String]
    /// Human-readable warnings without secret values.
    public var warnings: [String]

    /// Creates a validation report.
    public init(entryCount: Int, methodsAndPaths: [String], warnings: [String]) {
        self.entryCount = entryCount
        self.methodsAndPaths = methodsAndPaths
        self.warnings = warnings
    }
}

/// Validates HAR archives for common replay and safety issues.
public enum HARValidation {
    /// Validates a HAR archive and returns a human-readable report.
    public static func validate(_ archive: HARArchive) -> HARValidationReport {
        var methodsAndPaths: [String] = []
        var warnings: [String] = []

        for entry in archive.entries {
            if let components = URLComponents(string: entry.request.url) {
                let path = components.path.isEmpty ? PathUtilities.rootPath : components.path
                methodsAndPaths.append("\(entry.request.method.uppercased()) \(path)")
                if let scheme = components.scheme?.lowercased(), scheme == "ws" || scheme == "wss" {
                    warnings.append("Entry \(entry.index): unsupported WebSocket request at \(path)")
                }
            }

            for header in entry.request.headers where harSensitiveHeaderNames.contains(header.name.lowercased()) {
                warnings.append("Entry \(entry.index): sensitive request header \(header.name) detected")
            }
            for header in entry.response.headers where harSensitiveHeaderNames.contains(header.name.lowercased()) {
                warnings.append("Entry \(entry.index): sensitive response header \(header.name) detected")
            }
            for item in effectiveQueryItems(for: entry.request) where harSensitiveQueryNames.contains(item.name.lowercased()) {
                warnings.append("Entry \(entry.index): sensitive query item \(item.name) detected")
            }
            for key in sensitiveJSONKeys(in: entry.request.postData?.text) {
                warnings.append("Entry \(entry.index): sensitive JSON key \(key) detected in request body")
            }
            for key in sensitiveJSONKeys(in: entry.response.content) {
                warnings.append("Entry \(entry.index): sensitive JSON key \(key) detected in response body")
            }
            if let encoding = entry.response.content.encoding, encoding.lowercased() != "base64" {
                warnings.append("Entry \(entry.index): unsupported content encoding \(encoding)")
            }
            if entry.response.content.text == nil {
                warnings.append("Entry \(entry.index): missing response body")
            }
        }

        return HARValidationReport(entryCount: archive.entries.count, methodsAndPaths: methodsAndPaths, warnings: warnings)
    }
}

func sensitiveWarnings(in entry: HAREntry) -> [HARValidationWarning] {
    var warnings: [HARValidationWarning] = []

    for header in entry.request.headers where harSensitiveHeaderNames.contains(header.name.lowercased()) {
        warnings.append(HARValidationWarning(entryIndex: entry.index, message: "Sensitive request header \(header.name) detected"))
    }
    for header in entry.response.headers where harSensitiveHeaderNames.contains(header.name.lowercased()) {
        warnings.append(HARValidationWarning(entryIndex: entry.index, message: "Sensitive response header \(header.name) detected"))
    }
    for item in effectiveQueryItems(for: entry.request) where harSensitiveQueryNames.contains(item.name.lowercased()) {
        warnings.append(HARValidationWarning(entryIndex: entry.index, message: "Sensitive query item \(item.name) detected"))
    }
    for key in sensitiveJSONKeys(in: entry.request.postData?.text) {
        warnings.append(HARValidationWarning(entryIndex: entry.index, message: "Sensitive JSON key \(key) detected in request body"))
    }
    for key in sensitiveJSONKeys(in: entry.response.content) {
        warnings.append(HARValidationWarning(entryIndex: entry.index, message: "Sensitive JSON key \(key) detected in response body"))
    }

    return warnings
}

func effectiveQueryItems(for request: HARRequest) -> [HARNameValue] {
    if !request.queryString.isEmpty {
        return request.queryString
    }
    guard let components = URLComponents(string: request.url) else { return [] }
    return (components.queryItems ?? []).map { HARNameValue(name: $0.name, value: $0.value ?? "") }
}

func sensitiveJSONKeys(in text: String?) -> [String] {
    guard let text, let data = text.data(using: .utf8) else { return [] }
    guard let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
    var found: [String] = []
    collectSensitiveJSONKeys(from: json, into: &found)
    return found
}

func sensitiveJSONKeys(in content: HARContent) -> [String] {
    guard let text = content.text else { return [] }
    if content.encoding?.lowercased() == "base64",
       let data = Data(base64Encoded: text),
       let json = try? JSONSerialization.jsonObject(with: data) {
        var found: [String] = []
        collectSensitiveJSONKeys(from: json, into: &found)
        return found
    }
    return sensitiveJSONKeys(in: text)
}

private func collectSensitiveJSONKeys(from value: Any, into found: inout [String]) {
    if let dict = value as? [String: Any] {
        for (key, nested) in dict {
            if harSensitiveJSONKeys.contains(key.lowercased()) {
                found.append(key)
            }
            collectSensitiveJSONKeys(from: nested, into: &found)
        }
    } else if let array = value as? [Any] {
        for item in array {
            collectSensitiveJSONKeys(from: item, into: &found)
        }
    }
}

func sanitizedHeaderList(_ headers: [HARNameValue], stripSensitive: Bool, stripCookies: Bool) -> [HARNameValue] {
    headers.filter { header in
        let lowered = header.name.lowercased()
        if stripCookies && lowered == "set-cookie" { return false }
        if stripSensitive && harSensitiveHeaderNames.contains(lowered) { return false }
        return true
    }
}

func normalizedRequestHeaders(_ headers: [HARNameValue], includeHeaderMatching: Bool, stripSensitive: Bool) -> [HARNameValue] {
    guard includeHeaderMatching else { return [] }
    return headers.filter { header in
        let lowered = header.name.lowercased()
        return !volatileRequestHeaderNames.contains(lowered) && !(stripSensitive && harSensitiveHeaderNames.contains(lowered))
    }
}
