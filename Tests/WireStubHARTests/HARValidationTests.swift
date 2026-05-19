import XCTest
@testable import WireStubHAR

final class HARValidationTests: XCTestCase {
    func testValidateReportsEntryCount() throws {
        let archive = try HARTestHelpers.fixtureArchive("simple_get.har")
        let report = HARValidation.validate(archive)
        XCTAssertEqual(report.entryCount, 1)
    }

    func testValidateReportsMethodsAndPaths() throws {
        let archive = try HARTestHelpers.fixtureArchive("query_params.har")
        let report = HARValidation.validate(archive)
        XCTAssertEqual(report.methodsAndPaths, ["GET /search"])
    }

    func testValidateReportsSensitiveDataWarnings() throws {
        let archive = try HARTestHelpers.fixtureArchive("sensitive_headers.har")
        let report = HARValidation.validate(archive)
        XCTAssertFalse(report.warnings.isEmpty)
    }

    func testValidateReportsUnsupportedWebSocketEntries() throws {
        let data = Data(#"{"log":{"entries":[{"request":{"method":"GET","url":"ws://socket.example.com/connect","headers":[],"queryString":[]},"response":{"status":101,"headers":[],"content":{"mimeType":"text/plain","text":""}}}]}}"#.utf8)
        let archive = try HARLoader.load(data: data)
        let report = HARValidation.validate(archive)
        XCTAssertTrue(report.warnings.contains(where: { $0.contains("WebSocket") }))
    }

    func testValidateReportsUnsupportedCompressedOrMissingBodies() throws {
        let data = Data(#"{"log":{"entries":[{"request":{"method":"GET","url":"https://api.example.com/compressed","headers":[],"queryString":[]},"response":{"status":200,"headers":[],"content":{"mimeType":"application/json","encoding":"gzip","text":"abc"}}},{"request":{"method":"GET","url":"https://api.example.com/missing","headers":[],"queryString":[]},"response":{"status":200,"headers":[],"content":{"mimeType":"application/json"}}}]}}"#.utf8)
        let archive = try HARLoader.load(data: data)
        let report = HARValidation.validate(archive)
        XCTAssertTrue(report.warnings.contains(where: { $0.contains("encoding") }))
        XCTAssertTrue(report.warnings.contains(where: { $0.contains("missing response body") }))
    }

    func testValidateDoesNotMutateArchive() throws {
        let archive = try HARTestHelpers.fixtureArchive("simple_get.har")
        let original = archive
        _ = HARValidation.validate(archive)
        XCTAssertEqual(archive, original)
    }

    func testHARValidationWarningsDoNotLeakSensitiveValues() throws {
        let archive = try HARTestHelpers.fixtureArchive("sensitive_headers.har")
        let text = HARValidation.validate(archive).warnings.joined(separator: "\n")
        XCTAssertFalse(text.contains("super-secret-token"))
        XCTAssertFalse(text.contains("cookie-session-value"))
        XCTAssertFalse(text.contains("really-secret"))
    }
}
