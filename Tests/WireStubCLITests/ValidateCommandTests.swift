import XCTest
@testable import WireStubCLI

final class ValidateCommandTests: XCTestCase {
    func testValidatePassesForValidHAR() throws {
        let result = CLICommandRunner.validate(file: CLITestHelpers.fixtureURL("simple_get.har"), strict: false)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("Entry count: 1"))
        XCTAssertTrue(result.stdout.contains("Warnings: none"))
    }

    func testValidateReportsSensitiveWarningsWithoutValues() throws {
        let result = CLICommandRunner.validate(file: CLITestHelpers.fixtureURL("sensitive_headers.har"), strict: false)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("Sensitive request header Authorization detected"))
        XCTAssertFalse(result.stdout.contains("super-secret-token"))
        XCTAssertFalse(result.stdout.contains("cookie-session-value"))
        XCTAssertFalse(result.stdout.contains("really-secret"))
    }

    func testValidateStrictFailsOnWarnings() throws {
        let result = CLICommandRunner.validate(file: CLITestHelpers.fixtureURL("sensitive_headers.har"), strict: true)

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("Sensitive data warnings:"))
    }

    func testValidateFailsForMalformedHAR() throws {
        let result = CLICommandRunner.validate(file: CLITestHelpers.fixtureURL("malformed_missing_entries.har"), strict: false)

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("missing log.entries"))
    }
}
