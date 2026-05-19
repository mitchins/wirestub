import Foundation

/// Errors produced while loading a HAR archive.
public enum HARLoaderError: Error, LocalizedError, Equatable {
    case missingLog
    case missingEntries
    case invalidJSON
    case invalidBase64Body

    /// Human-readable loader error.
    public var errorDescription: String? {
        switch self {
        case .missingLog:
            return "HAR document is missing log"
        case .missingEntries:
            return "HAR document is missing log.entries"
        case .invalidJSON:
            return "HAR document is not valid JSON"
        case .invalidBase64Body:
            return "HAR response body declared as base64 could not be decoded"
        }
    }
}

private struct DecodedHAREntry: Decodable {
    let request: HARRequest
    let response: HARResponse
}

/// Loads raw HAR documents into `HARArchive` values.
public enum HARLoader {
    /// Loads a HAR archive from disk.
    public static func load(from url: URL) throws -> HARArchive {
        try load(data: Data(contentsOf: url))
    }

    /// Loads a HAR archive from raw JSON data.
    public static func load(data: Data) throws -> HARArchive {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw HARLoaderError.invalidJSON
        }
        guard let root = object as? [String: Any], let log = root["log"] as? [String: Any] else {
            throw HARLoaderError.missingLog
        }
        guard let entriesObject = log["entries"] as? [Any] else {
            throw HARLoaderError.missingEntries
        }
        let entriesData = try JSONSerialization.data(withJSONObject: entriesObject)
        let decodedEntries: [DecodedHAREntry]
        do {
            decodedEntries = try JSONDecoder().decode([DecodedHAREntry].self, from: entriesData)
        } catch {
            throw HARLoaderError.invalidJSON
        }
        return HARArchive(entries: decodedEntries.enumerated().map { index, entry in
            HAREntry(index: index, request: entry.request, response: entry.response)
        })
    }
}
