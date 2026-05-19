import Foundation
import XCTest
import WireStubCore
import WireStubServer
@testable import WireStubURLProtocol

enum URLProtocolTestHelpers {
    static let apiBaseURL = URL(string: "https://api.example.com")!

    static func withInstalledSession<T>(
        scenario: StubScenario,
        _ body: (URLSession, URLProtocolInstallation) async throws -> T
    ) async throws -> T {
        let configuration = URLSessionConfiguration.ephemeral
        let installation = URLProtocolInstaller.install(scenario: scenario, into: configuration)
        let session = URLSession(configuration: configuration)
        defer {
            session.invalidateAndCancel()
            installation.invalidate()
        }
        return try await body(session, installation)
    }

    static func withStartedServer<T>(
        scenario: StubScenario,
        _ body: (LocalStubServer) async throws -> T
    ) async throws -> T {
        let server = try LocalStubServer(scenario: scenario)
        try await server.start()
        do {
            let value = try await body(server)
            await server.stop()
            return value
        } catch {
            await server.stop()
            throw error
        }
    }

    static func makeRequest(
        baseURL: URL = apiBaseURL,
        method: String = "GET",
        path: String,
        queryItems: [URLQueryItem] = [],
        headers: [String: String] = [:],
        body: Data? = nil
    ) -> URLRequest {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.httpBody = body
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        return request
    }

    static func perform(_ request: URLRequest, session: URLSession) async throws -> (HTTPURLResponse, Data) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(
                domain: "WireStubURLProtocolTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Expected HTTPURLResponse"]
            )
        }
        return (http, data)
    }

    static func performServerRequest(_ request: URLRequest) async throws -> (HTTPURLResponse, Data) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(
                domain: "WireStubURLProtocolTests",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Expected HTTPURLResponse"]
            )
        }
        return (http, data)
    }

    static func matchedOutcome(_ entry: JournalEntry) -> (routeID: String, status: Int)? {
        guard case .matched(let routeID, let status) = entry.outcome else {
            return nil
        }
        return (routeID, status)
    }
}
