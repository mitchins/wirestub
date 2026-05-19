import XCTest
@testable import WireStubHAR

final class HARParsingTests: XCTestCase {
    func testLoadsHARLogEntries() throws {
        let archive = try HARTestHelpers.fixtureArchive("simple_get.har")
        XCTAssertEqual(archive.entries.count, 1)
    }

    func testParsesRequestMethodAndURL() throws {
        let archive = try HARTestHelpers.fixtureArchive("simple_get.har")
        let request = try XCTUnwrap(archive.entries.first?.request)
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.url, "https://api.example.com/users")
    }

    func testParsesRequestHeaders() throws {
        let archive = try HARTestHelpers.fixtureArchive("simple_get.har")
        let headers = try XCTUnwrap(archive.entries.first?.request.headers)
        XCTAssertEqual(headers.first(where: { $0.name == "Accept" })?.value, "application/json")
    }

    func testParsesRequestPostData() throws {
        let archive = try HARTestHelpers.fixtureArchive("post_json.har")
        let postData = try XCTUnwrap(archive.entries.first?.request.postData)
        XCTAssertEqual(postData.mimeType, "application/json")
        XCTAssertTrue(postData.text?.contains("name") == true)
    }

    func testParsesResponseStatusHeadersAndBody() throws {
        let archive = try HARTestHelpers.fixtureArchive("simple_get.har")
        let response = try XCTUnwrap(archive.entries.first?.response)
        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(response.headers.first(where: { $0.name == "Content-Type" })?.value, "application/json")
        XCTAssertEqual(response.content.text, #"{"id":1,"name":"Blob"}"#)
    }

    func testDecodesBase64ResponseBody() throws {
        let archive = try HARTestHelpers.fixtureArchive("base64_response.har")
        let response = try XCTUnwrap(archive.entries.first?.response)
        XCTAssertEqual(response.content.encoding, "base64")
        XCTAssertEqual(try response.decodedBody(decodeBase64Bodies: true), Data([0, 0, 0]))
    }

    func testThrowsUsefulErrorForMissingLog() throws {
        XCTAssertThrowsError(try HARTestHelpers.fixtureArchive("malformed_missing_log.har")) { error in
            XCTAssertEqual(error as? HARLoaderError, .missingLog)
        }
    }

    func testThrowsUsefulErrorForMissingEntries() throws {
        XCTAssertThrowsError(try HARTestHelpers.fixtureArchive("malformed_missing_entries.har")) { error in
            XCTAssertEqual(error as? HARLoaderError, .missingEntries)
        }
    }

    func testHARParserDoesNotCrashOnDuplicateHeaders() throws {
        let data = Data(#"{"log":{"entries":[{"request":{"method":"GET","url":"https://api.example.com/users","headers":[{"name":"Accept","value":"application/json"},{"name":"Accept","value":"text/plain"}],"queryString":[]},"response":{"status":200,"headers":[{"name":"Set-Cookie","value":"a=1"},{"name":"Set-Cookie","value":"b=2"}],"content":{"mimeType":"application/json","text":"{}"}}}]}}"#.utf8)
        let archive = try HARLoader.load(data: data)
        XCTAssertEqual(archive.entries.first?.request.headers.count, 2)
        XCTAssertEqual(archive.entries.first?.response.headers.count, 2)
    }
}
