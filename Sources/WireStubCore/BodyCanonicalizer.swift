import Foundation
import CryptoKit

// MARK: - BodyCanonicalizer

/// Provides deterministic body hashing for matching.
public enum BodyCanonicalizer {

    // MARK: Raw hash

    /// SHA-256 of the raw body bytes. Returns a lowercase hex string.
    public static func rawHash(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Canonical JSON hash

    /// Result of canonical JSON hashing, including deterministic fallback metadata.
    public struct CanonicalResult: Sendable {
        /// The resulting SHA-256 hash, either canonical JSON or raw bytes when fallback was required.
        public let hash: String
        /// Whether canonical JSON parsing failed and raw hashing was used instead.
        public let canonicalizationFailed: Bool
        /// If canonicalization failed, this explains why and raw body hash was used instead.
        public let failureReason: String?
        /// Which side failed canonicalization when fallback was required.
        public let side: CanonicalFailureSide?
    }

    /// Attempts to produce a canonical JSON hash (key-sorted, array-order-preserved SHA-256).
    /// If the body cannot be parsed as JSON, falls back deterministically to raw body SHA256
    /// and reports `canonicalizationFailed = true`.
    public static func canonicalJSONHash(
        _ data: Data,
        fallbackSide: CanonicalFailureSide = .request
    ) -> CanonicalResult {
        do {
            let sorted = try canonicalizeJSON(data)
            let hash = rawHash(sorted)
            return CanonicalResult(hash: hash, canonicalizationFailed: false, failureReason: nil, side: nil)
        } catch {
            let fallback = rawHash(data)
            return CanonicalResult(
                hash: fallback,
                canonicalizationFailed: true,
                failureReason: error.localizedDescription,
                side: fallbackSide
            )
        }
    }

    // MARK: - Internal

    static func canonicalizeJSON(_ data: Data) throws -> Data {
        let obj = try JSONSerialization.jsonObject(with: data, options: [])
        let sorted = sortedJSONValue(obj)
        return try JSONSerialization.data(withJSONObject: sorted, options: [.sortedKeys])
    }

    /// Recursively sort all dictionary keys; preserve array order.
    private static func sortedJSONValue(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            return dict.mapValues { sortedJSONValue($0) }
        } else if let array = value as? [Any] {
            return array.map { sortedJSONValue($0) }
        }
        return value
    }
}
