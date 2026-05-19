import Foundation
import XCTest
import Darwin
@testable import WireStubServer
import WireStubCore

enum ServerTestHelpers {
    static func withStartedServer<T>(
        scenario: StubScenario,
        file: StaticString = #file,
        line: UInt = #line,
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
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return request
    }

    static func perform(_ request: URLRequest) async throws -> (HTTPURLResponse, Data) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "WireStubTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected HTTPURLResponse"])
        }
        return (http, data)
    }

    static func headerValue(_ name: String, in headers: WireStubCore.HTTPHeaders) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    static func queryValue(_ name: String, in queryItems: [WireStubCore.QueryItem]) -> String? {
        queryItems.first { $0.name == name }?.value
    }

    static func waitUntilPortIsBindable(_ port: Int, attempts: Int = 40) async -> Bool {
        for _ in 0..<attempts {
            if canBindLoopbackPort(port) {
                return true
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }

    static func canBindLoopbackPort(_ port: Int) -> Bool {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }

        var value: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &value, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port).bigEndian)
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return bindResult == 0
    }
}
