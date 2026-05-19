import Foundation
import XCTest
@testable import WireStubCLI
import WireStubHAR

final class SanitizeCommandTests: XCTestCase {
    func testSanitizeWritesLoadableHAR() throws {
        let directory = try CLITestHelpers.temporaryDirectory()
        let outputURL = directory.appendingPathComponent("sanitized.har")

        let result = CLICommandRunner.sanitize(
            input: CLITestHelpers.fixtureURL("sensitive_headers.har"),
            output: outputURL,
            removeHeaders: [],
            redactQueryItems: [],
            redactJSONKeys: []
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertNoThrow(try HARLoader.load(from: outputURL))
    }

    func testSanitizeRemovesAuthorizationCookieAndSetCookie() throws {
        let directory = try CLITestHelpers.temporaryDirectory()
        let outputURL = directory.appendingPathComponent("sanitized.har")

        _ = CLICommandRunner.sanitize(
            input: CLITestHelpers.fixtureURL("sensitive_headers.har"),
            output: outputURL,
            removeHeaders: [],
            redactQueryItems: [],
            redactJSONKeys: []
        )

        let archive = try HARLoader.load(from: outputURL)
        let entry = try XCTUnwrap(archive.entries.first)
        XCTAssertFalse(entry.request.headers.contains(where: { ["authorization", "cookie"].contains($0.name.lowercased()) }))
        XCTAssertFalse(entry.response.headers.contains(where: { $0.name.lowercased() == "set-cookie" }))
    }

    func testSanitizeRedactsSensitiveQueryItems() throws {
        let directory = try CLITestHelpers.temporaryDirectory()
        let outputURL = directory.appendingPathComponent("sanitized.har")

        _ = CLICommandRunner.sanitize(
            input: CLITestHelpers.fixtureURL("sensitive_headers.har"),
            output: outputURL,
            removeHeaders: [],
            redactQueryItems: [],
            redactJSONKeys: []
        )

        let archive = try HARLoader.load(from: outputURL)
        let value = archive.entries.first?.request.queryString.first(where: { $0.name == "access_token" })?.value
        XCTAssertEqual(value, HARSanitizer.redactedPlaceholder)
    }

    func testSanitizeRedactsSensitiveJSONKeys() throws {
        let directory = try CLITestHelpers.temporaryDirectory()
        let outputURL = directory.appendingPathComponent("sanitized.har")

        _ = CLICommandRunner.sanitize(
            input: CLITestHelpers.fixtureURL("sensitive_headers.har"),
            output: outputURL,
            removeHeaders: [],
            redactQueryItems: [],
            redactJSONKeys: []
        )

        let data = try Data(contentsOf: outputURL)
        let string = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(string.contains("really-secret"))
        XCTAssertFalse(string.contains("hunter2"))
    }

    func testSanitizePreservesNonSensitiveEntries() throws {
        let directory = try CLITestHelpers.temporaryDirectory()
        let outputURL = directory.appendingPathComponent("sanitized.har")

        let result = CLICommandRunner.sanitize(
            input: CLITestHelpers.fixtureURL("simple_get.har"),
            output: outputURL,
            removeHeaders: [],
            redactQueryItems: [],
            redactJSONKeys: []
        )

        XCTAssertEqual(result.exitCode, 0)
        let sanitized = try HARLoader.load(from: outputURL)
        let original = try HARLoader.load(from: CLITestHelpers.fixtureURL("simple_get.har"))
        XCTAssertEqual(sanitized.entries.first?.request.url, original.entries.first?.request.url)
        XCTAssertEqual(sanitized.entries.first?.response.status, original.entries.first?.response.status)
    }

    func testSanitizeDoesNotPrintSensitiveValues() throws {
        let directory = try CLITestHelpers.temporaryDirectory()
        let outputURL = directory.appendingPathComponent("sanitized.har")

        let result = CLICommandRunner.sanitize(
            input: CLITestHelpers.fixtureURL("sensitive_headers.har"),
            output: outputURL,
            removeHeaders: [],
            redactQueryItems: [],
            redactJSONKeys: []
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertFalse(result.stdout.contains("super-secret-token"))
        XCTAssertFalse(result.stdout.contains("cookie-session-value"))
        XCTAssertFalse(result.stdout.contains("really-secret"))
        XCTAssertFalse(result.stdout.contains("hunter2"))
    }

    func testSanitizeDoesNotOverwriteInputByDefault() throws {
        let directory = try CLITestHelpers.temporaryDirectory()
        let inputURL = directory.appendingPathComponent("input.har")
        try Data(contentsOf: CLITestHelpers.fixtureURL("sensitive_headers.har")).write(to: inputURL)
        let original = try Data(contentsOf: inputURL)

        let result = CLICommandRunner.sanitize(
            input: inputURL,
            output: inputURL,
            removeHeaders: [],
            redactQueryItems: [],
            redactJSONKeys: []
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertEqual(try Data(contentsOf: inputURL), original)
    }
}
