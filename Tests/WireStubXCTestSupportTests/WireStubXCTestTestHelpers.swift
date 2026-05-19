import Foundation
import XCTest
@testable import WireStubXCTest
import WireStubServer
import WireStubCore

final class FakeLaunchConfigurable: WireStubLaunchConfigurable {
    var launchEnvironment: [String: String] = [:]
}

enum WireStubXCTestTestHelpers {
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
        baseURL: URL,
        method: String = "GET",
        path: String,
        headers: [String: String] = [:],
        body: Data? = nil
    ) -> URLRequest {
        let url = URL(string: path, relativeTo: baseURL)!.absoluteURL
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return request
    }

    static func perform(_ request: URLRequest) async throws {
        _ = try await URLSession.shared.data(for: request)
    }

    static func message(from error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return String(describing: error)
    }
}

extension URLRequest {
    func setting(method: String) -> URLRequest {
        var copy = self
        copy.httpMethod = method
        return copy
    }
}
