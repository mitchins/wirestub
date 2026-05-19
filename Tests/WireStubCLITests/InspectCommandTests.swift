import XCTest
@testable import WireStubCLI

final class InspectCommandTests: XCTestCase {
    func testInspectPrintsEntryCountMethodsAndPaths() throws {
        let result = CLICommandRunner.inspect(file: CLITestHelpers.fixtureURL("simple_get.har"))

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("Entry count: 1"))
        XCTAssertTrue(result.stdout.contains("GET /users"))
        XCTAssertTrue(result.stdout.contains("Status codes: 200"))
    }

    func testInspectDoesNotPrintSensitiveValues() throws {
        let result = CLICommandRunner.inspect(file: CLITestHelpers.fixtureURL("sensitive_headers.har"))

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("Sensitive data detected: yes"))
        XCTAssertFalse(result.stdout.contains("super-secret-token"))
        XCTAssertFalse(result.stdout.contains("cookie-session-value"))
        XCTAssertFalse(result.stdout.contains("really-secret"))
    }

    func testInspectFailsForMissingFile() throws {
        let result = CLICommandRunner.inspect(file: URL(fileURLWithPath: "/tmp/does-not-exist.har"))

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.localizedCaseInsensitiveContains("not found"))
    }

    func testInspectFailsForMalformedHAR() throws {
        let result = CLICommandRunner.inspect(file: CLITestHelpers.fixtureURL("malformed_missing_log.har"))

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("missing log"))
    }
}
