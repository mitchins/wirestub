import XCTest
@testable import WireStubHAR

final class HARSanitizerTests: XCTestCase {
    func testSanitizerRemovesAuthorizationHeader() throws {
        let archive = try HARTestHelpers.fixtureArchive("sensitive_headers.har")
        let sanitized = HARSanitizer.sanitize(archive)
        XCTAssertFalse(sanitized.entries.first?.request.headers.contains(where: { $0.name == "Authorization" }) == true)
    }

    func testSanitizerRemovesCookieHeader() throws {
        let archive = try HARTestHelpers.fixtureArchive("sensitive_headers.har")
        let sanitized = HARSanitizer.sanitize(archive)
        XCTAssertFalse(sanitized.entries.first?.request.headers.contains(where: { $0.name == "Cookie" }) == true)
    }

    func testSanitizerRemovesSetCookieHeader() throws {
        let archive = try HARTestHelpers.fixtureArchive("sensitive_headers.har")
        let sanitized = HARSanitizer.sanitize(archive)
        XCTAssertFalse(sanitized.entries.first?.response.headers.contains(where: { $0.name == "Set-Cookie" }) == true)
    }

    func testSanitizerRedactsConfiguredQueryItems() throws {
        let archive = try HARTestHelpers.fixtureArchive("sensitive_headers.har")
        let sanitized = HARSanitizer.sanitize(archive)
        let queryValue = sanitized.entries.first?.request.queryString.first(where: { $0.name == "access_token" })?.value
        XCTAssertEqual(queryValue, HARSanitizer.redactedPlaceholder)
    }

    func testSanitizerRedactsConfiguredJSONKeys() throws {
        let archive = try HARTestHelpers.fixtureArchive("sensitive_headers.har")
        let sanitized = HARSanitizer.sanitize(archive)
        XCTAssertFalse(sanitized.entries.first?.request.postData?.text?.contains("really-secret") == true)
        XCTAssertTrue(sanitized.entries.first?.request.postData?.text?.contains(HARSanitizer.redactedPlaceholder) == true)
    }

    func testSanitizerPreservesNonSensitiveEntries() throws {
        let archive = try HARTestHelpers.fixtureArchive("simple_get.har")
        let sanitized = HARSanitizer.sanitize(archive)
        XCTAssertEqual(sanitized.entries.first?.request.url, archive.entries.first?.request.url)
        XCTAssertEqual(sanitized.entries.first?.response.status, archive.entries.first?.response.status)
    }

    func testSanitizerOutputCanBeLoadedAgain() throws {
        let archive = try HARTestHelpers.fixtureArchive("sensitive_headers.har")
        let sanitized = HARSanitizer.sanitize(archive)
        let data = try HARSanitizer.data(from: sanitized)
        let reloaded = try HARLoader.load(data: data)
        XCTAssertEqual(reloaded.entries.count, sanitized.entries.count)
    }
}
