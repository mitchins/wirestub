import XCTest
@testable import WireStubCore

final class BodyCanonicalizationTests: XCTestCase {

    func testRawBodyHashIsStable() {
        let data = "hello world".data(using: .utf8)!
        let h1 = BodyCanonicalizer.rawHash(data)
        let h2 = BodyCanonicalizer.rawHash(data)
        XCTAssertEqual(h1, h2)
        XCTAssertFalse(h1.isEmpty)
    }

    func testCanonicalJSONHashIgnoresObjectKeyOrder() throws {
        let a = "{\"b\":2,\"a\":1}".data(using: .utf8)!
        let b = "{\"a\":1,\"b\":2}".data(using: .utf8)!
        let hashA = BodyCanonicalizer.canonicalJSONHash(a)
        let hashB = BodyCanonicalizer.canonicalJSONHash(b)
        XCTAssertFalse(hashA.canonicalizationFailed)
        XCTAssertFalse(hashB.canonicalizationFailed)
        XCTAssertEqual(hashA.hash, hashB.hash, "Key order must not affect canonical hash")
    }

    func testCanonicalJSONHashPreservesArrayOrder() throws {
        let a = "[1,2,3]".data(using: .utf8)!
        let b = "[3,2,1]".data(using: .utf8)!
        let hashA = BodyCanonicalizer.canonicalJSONHash(a)
        let hashB = BodyCanonicalizer.canonicalJSONHash(b)
        XCTAssertFalse(hashA.canonicalizationFailed)
        XCTAssertFalse(hashB.canonicalizationFailed)
        XCTAssertNotEqual(hashA.hash, hashB.hash, "Array order must be preserved")
    }

    func testCanonicalJSONHashDistinguishesDifferentValues() throws {
        let a = "{\"x\":1}".data(using: .utf8)!
        let b = "{\"x\":2}".data(using: .utf8)!
        let hashA = BodyCanonicalizer.canonicalJSONHash(a)
        let hashB = BodyCanonicalizer.canonicalJSONHash(b)
        XCTAssertNotEqual(hashA.hash, hashB.hash)
    }

    func testMalformedJSONFallsBackToRawBodyOrFailsDeterministically() {
        let malformed = "not json {{{".data(using: .utf8)!
        let result = BodyCanonicalizer.canonicalJSONHash(malformed)

        XCTAssertTrue(result.canonicalizationFailed, "Malformed JSON must set canonicalizationFailed")
        XCTAssertNotNil(result.failureReason)
        // Fallback must be deterministic: same input → same hash
        let result2 = BodyCanonicalizer.canonicalJSONHash(malformed)
        XCTAssertEqual(result.hash, result2.hash, "Fallback must be deterministic")
        // Fallback hash must equal raw hash
        XCTAssertEqual(result.hash, BodyCanonicalizer.rawHash(malformed))
    }

    func testEmptyBodyAndMissingBodyAreHandledDistinctlyOrDocumented() {
        let emptyData = Data()
        let emptyResult = BodyCanonicalizer.rawHash(emptyData)

        // Document the distinction: empty Data and nil body are treated as empty Data in matching.
        // They must produce a stable, deterministic hash (not crash or produce different results each run).
        XCTAssertFalse(emptyResult.isEmpty)

        let emptyResult2 = BodyCanonicalizer.rawHash(emptyData)
        XCTAssertEqual(emptyResult, emptyResult2, "Empty body hash must be stable")
    }
}
