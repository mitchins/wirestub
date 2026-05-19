import Foundation
import XCTest
@testable import WireStubHAR
import WireStubCore

enum HARTestHelpers {
    static func fixtureURL(_ name: String, file: StaticString = #filePath) -> URL {
        let fileURL = URL(fileURLWithPath: String(describing: file))
        return fileURL.deletingLastPathComponent().appendingPathComponent("HARFixtures").appendingPathComponent(name)
    }

    static func fixtureData(_ name: String, file: StaticString = #filePath) throws -> Data {
        try Data(contentsOf: fixtureURL(name, file: file))
    }

    static func fixtureArchive(_ name: String, file: StaticString = #filePath) throws -> HARArchive {
        try HARLoader.load(from: fixtureURL(name, file: file))
    }
}

extension RequestSnapshot {
    static func harGet(_ path: String, queryItems: [QueryItem] = [], headers: HTTPHeaders = [:]) -> RequestSnapshot {
        RequestSnapshot(
            method: "GET",
            path: path,
            target: RequestTarget(scheme: "http", host: "127.0.0.1", port: 8080),
            queryItems: queryItems,
            headers: headers
        )
    }

    static func harPost(_ path: String, queryItems: [QueryItem] = [], headers: HTTPHeaders = [:], body: Data? = nil) -> RequestSnapshot {
        RequestSnapshot(
            method: "POST",
            path: path,
            target: RequestTarget(scheme: "http", host: "127.0.0.1", port: 8080),
            queryItems: queryItems,
            headers: headers,
            body: body
        )
    }
}
