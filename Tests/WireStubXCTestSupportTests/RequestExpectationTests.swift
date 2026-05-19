import XCTest
@testable import WireStubXCTest
import WireStubCore

final class RequestExpectationTests: XCTestCase {
    func testExpectationMatchesMethodPathHeadersAndQuerySubset() {
        let expectation = RequestExpectation.get(
            "/feed",
            queryItems: [QueryItem(name: "page", value: "1")],
            headers: ["Authorization": "Bearer token"]
        )
        let request = RequestSnapshot(
            method: "GET",
            path: "/feed",
            queryItems: [
                QueryItem(name: "page", value: "1"),
                QueryItem(name: "source", value: "home"),
            ],
            headers: ["Authorization": "Bearer token"]
        )

        XCTAssertTrue(expectation.matches(request))
    }

    func testExpectationDoesNotMatchWhenRequiredHeaderDiffers() {
        let expectation = RequestExpectation.get("/feed", headers: ["Authorization": "Bearer token"])
        let request = RequestSnapshot(method: "GET", path: "/feed", headers: ["Authorization": "Bearer other"])

        XCTAssertFalse(expectation.matches(request))
    }

    func testExpectationMatchesExactBodyBytes() {
        let body = Data("refresh=stale".utf8)
        let expectation = RequestExpectation.post("/auth/refresh", body: body)
        let request = RequestSnapshot(method: "POST", path: "/auth/refresh", body: body)

        XCTAssertTrue(expectation.matches(request))
    }

    func testExpectationMatchesCanonicalJSONBody() throws {
        let expectation = try RequestExpectation.patch("/profile", jsonBody: ["a": 1, "b": 2])
        let request = RequestSnapshot(
            method: "PATCH",
            path: "/profile",
            body: #"{"b":2,"a":1}"#.data(using: .utf8)!
        )

        XCTAssertTrue(expectation.matches(request))
    }

    func testExpectationDeleteAndPutBuildersUseExpectedMethods() {
        XCTAssertEqual(RequestExpectation.delete("/account").method, "DELETE")
        XCTAssertEqual(RequestExpectation.put("/profile").method, "PUT")
    }

    func testExpectationDescriptionIncludesRedactedTargetAndMetadata() throws {
        let expectation = try RequestExpectation.post(
            "/auth/refresh",
            queryItems: [QueryItem(name: "token", value: "secret")],
            headers: ["Authorization": "Bearer secret"],
            jsonBody: ["refreshToken": "secret"]
        )

        XCTAssertTrue(expectation.description.contains("POST /auth/refresh?token=[REDACTED]"))
        XCTAssertTrue(expectation.description.contains("headers: Authorization"))
        XCTAssertTrue(expectation.description.contains("json body"))
    }
}
