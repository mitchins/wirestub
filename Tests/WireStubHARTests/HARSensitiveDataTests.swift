import Foundation
import XCTest
@testable import WireStubHAR
import WireStubCore

final class HARSensitiveDataTests: XCTestCase {
    func testSensitiveHeadersAreDetected() throws {
        let archive = try HARTestHelpers.fixtureArchive("sensitive_headers.har")
        let report = HARValidation.validate(archive)
        XCTAssertTrue(report.warnings.contains(where: { $0.contains("Authorization") }))
        XCTAssertTrue(report.warnings.contains(where: { $0.contains("Cookie") }))
    }

    func testAuthorizationHeaderValueIsRedactedInDiagnostics() throws {
        let archive = try HARTestHelpers.fixtureArchive("sensitive_headers.har")
        let report = HARValidation.validate(archive)
        XCTAssertFalse(report.warnings.joined(separator: " ").contains("super-secret-token"))
    }

    func testCookieHeaderValueIsRedactedInDiagnostics() throws {
        let archive = try HARTestHelpers.fixtureArchive("sensitive_headers.har")
        let report = HARValidation.validate(archive)
        XCTAssertFalse(report.warnings.joined(separator: " ").contains("cookie-session-value"))
    }

    func testSetCookieResponseHeaderCanBeStripped() throws {
        let archive = try HARTestHelpers.fixtureArchive("sensitive_headers.har")
        var options = HARImportOptions.standard
        options.sensitiveHeaderPolicy = .strip
        let scenario = try HARNormalizer.scenario(from: archive, options: options)
        guard case .staticResponse(let response) = try XCTUnwrap(scenario.routes.first?.responseProvider) else { return XCTFail("Expected response") }
        XCTAssertNil(response.headers["Set-Cookie"])
    }

    func testSensitiveQueryItemsAreDetected() throws {
        let archive = try HARTestHelpers.fixtureArchive("sensitive_headers.har")
        let report = HARValidation.validate(archive)
        XCTAssertTrue(report.warnings.contains(where: { $0.contains("access_token") }))
    }

    func testSensitiveJSONKeysAreDetectedOrRedacted() throws {
        let archive = try HARTestHelpers.fixtureArchive("sensitive_headers.har")
        let sanitized = HARSanitizer.sanitize(archive)
        let data = try HARSanitizer.data(from: sanitized)
        let string = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(string.contains("really-secret"))
        XCTAssertTrue(string.contains("access_token"))
    }

    func testFailPolicyThrowsWhenSensitiveHeadersPresent() throws {
        let archive = try HARTestHelpers.fixtureArchive("sensitive_headers.har")
        var options = HARImportOptions.standard
        options.sensitiveHeaderPolicy = .fail
        XCTAssertThrowsError(try HARNormalizer.scenario(from: archive, options: options))
    }

    func testWarnPolicyReturnsWarningsWithoutLeakingValues() throws {
        let archive = try HARTestHelpers.fixtureArchive("sensitive_headers.har")
        let report = HARValidation.validate(archive)
        let text = report.warnings.joined(separator: "\n")
        XCTAssertTrue(text.contains("Authorization"))
        XCTAssertFalse(text.contains("super-secret-token"))
        XCTAssertFalse(text.contains("cookie-session-value"))
    }

    func testSensitiveHeaderPolicyWarnProducesStructuredWarnings() throws {
        let archive = try HARTestHelpers.fixtureArchive("sensitive_headers.har")
        var options = HARImportOptions.standard
        options.sensitiveHeaderPolicy = .warn
        let result = try HARNormalizer.normalize(archive, options: options)
        XCTAssertFalse(result.warnings.isEmpty)
    }

    func testSensitiveHeaderPolicyWarnWarningsDoNotLeakValues() throws {
        let archive = try HARTestHelpers.fixtureArchive("sensitive_headers.har")
        var options = HARImportOptions.standard
        options.sensitiveHeaderPolicy = .warn
        let warnings = try HARNormalizer.normalize(archive, options: options).warnings.map(\.message).joined(separator: "\n")
        XCTAssertFalse(warnings.contains("super-secret-token"))
        XCTAssertFalse(warnings.contains("cookie-session-value"))
        XCTAssertFalse(warnings.contains("really-secret"))
    }

    func testSanitizerRedactsSensitiveValuesInsideRequestURL() throws {
        let archive = try HARTestHelpers.fixtureArchive("sensitive_headers.har")
        let sanitized = HARSanitizer.sanitize(archive)
        let requestURL = try XCTUnwrap(sanitized.entries.first?.request.url)
        let components = try XCTUnwrap(URLComponents(string: requestURL))
        let accessToken = components.queryItems?.first(where: { $0.name == "access_token" })?.value
        XCTAssertEqual(accessToken, HARSanitizer.redactedPlaceholder)
        XCTAssertFalse(requestURL.contains("token-value"))
    }

    func testBase64EncodedJSONResponseIsReportedAndRedacted() throws {
        let body = #"{"access_token":"really-secret","password":"hunter2"}"#.data(using: .utf8)!
        let archive = HARArchive(entries: [
            HAREntry(
                index: 0,
                request: HARRequest(method: "GET", url: "https://api.example.com/profile"),
                response: HARResponse(
                    status: 200,
                    content: HARContent(
                        mimeType: "application/json",
                        text: body.base64EncodedString(),
                        encoding: "base64"
                    )
                )
            )
        ])

        let report = HARValidation.validate(archive)
        XCTAssertTrue(report.warnings.contains(where: { $0.contains("access_token") }))
        XCTAssertFalse(report.warnings.joined(separator: " ").contains("really-secret"))

        let sanitized = HARSanitizer.sanitize(archive)
        let sanitizedBody = try XCTUnwrap(sanitized.entries.first?.response.content.text)
        let decoded = try XCTUnwrap(Data(base64Encoded: sanitizedBody))
        let json = String(decoding: decoded, as: UTF8.self)
        XCTAssertFalse(json.contains("really-secret"))
        XCTAssertFalse(json.contains("hunter2"))
        XCTAssertTrue(json.contains(HARSanitizer.redactedPlaceholder))
    }

    func testRelativeHARRequestURLIsRejected() {
        let archive = HARArchive(entries: [
            HAREntry(
                index: 0,
                request: HARRequest(method: "GET", url: "/users"),
                response: HARResponse(status: 200, content: HARContent())
            )
        ])

        XCTAssertThrowsError(try HARNormalizer.normalize(archive)) { error in
            guard let normalizedError = error as? HARNormalizerError else {
                return XCTFail("Expected HARNormalizerError")
            }
            XCTAssertEqual(normalizedError, .invalidURL("/users", entryIndex: 0))
        }
    }

    func testSensitiveHeaderPolicyStripRemovesSensitiveHeaders() throws {
        let archive = try HARTestHelpers.fixtureArchive("sensitive_headers.har")
        var options = HARImportOptions.standard
        options.sensitiveHeaderPolicy = .strip
        options.includeHeaderMatching = true
        let scenario = try HARNormalizer.normalize(archive, options: options).scenario
        let route = try XCTUnwrap(scenario.routes.first)
        XCTAssertNil(route.matcher.headers["Authorization"])
        guard case .staticResponse(let response) = route.responseProvider else {
            return XCTFail("Expected static response")
        }
        XCTAssertNil(response.headers["Set-Cookie"])
    }

    func testSensitiveHeaderPolicyFailThrows() throws {
        let archive = try HARTestHelpers.fixtureArchive("sensitive_headers.har")
        var options = HARImportOptions.standard
        options.sensitiveHeaderPolicy = .fail
        XCTAssertThrowsError(try HARNormalizer.normalize(archive, options: options))
    }
}
