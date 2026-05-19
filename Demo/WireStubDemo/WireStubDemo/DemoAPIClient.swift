import Foundation

struct DemoFlowResult {
    var userName: String
    var feedMessage: String
}

enum DemoBootstrapResult {
    case feedReady(DemoFlowResult)
    case sessionExpired
}

struct DemoUser: Decodable {
    var name: String
}

struct DemoFeed: Decodable {
    var message: String
}

enum DemoAPIError: LocalizedError {
    case invalidBaseURL
    case invalidResponse
    case missingSeededSession
    case unexpectedStatus(Int, path: String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "API_BASE_URL or AUTH_BASE_URL is missing or invalid."
        case .invalidResponse:
            return "The server returned an invalid response."
        case .missingSeededSession:
            return "No cached session was seeded by the consumer app."
        case .unexpectedStatus(let status, let path):
            return "Unexpected status \(status) for \(path)."
        }
    }
}

private struct DemoSessionState {
    var userName: String?
    var token: String

    static func seeded(from environment: [String: String]) -> DemoSessionState? {
        guard environment["DEMO_BOOTSTRAP_STATE"] == "authenticated-stale" else {
            return nil
        }
        return DemoSessionState(userName: "Cached Blob", token: "stale-token")
    }
}

private enum DemoBackend {
    case api
    case auth
}

final class DemoAPIClient {
    private let session: URLSession
    private let decoder: JSONDecoder
    private let apiBaseURL: URL
    private let authBaseURL: URL
    private var sessionState: DemoSessionState?

    var hasCachedSession: Bool {
        sessionState != nil
    }

    init(
        session: URLSession = .shared,
        decoder: JSONDecoder = JSONDecoder(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.session = session
        self.decoder = decoder
        let invalidURL = URL(string: "https://invalid.wirestub.local")!
        let resolvedAPIBaseURL = Self.validBaseURL(named: "API_BASE_URL", environment: environment)
        let resolvedAuthBaseURL = Self.validBaseURL(named: "AUTH_BASE_URL", environment: environment) ?? resolvedAPIBaseURL
        self.apiBaseURL = resolvedAPIBaseURL ?? invalidURL
        self.authBaseURL = resolvedAuthBaseURL ?? invalidURL
        self.sessionState = DemoSessionState.seeded(from: environment)
    }

    func runLoginFlow() async throws -> DemoFlowResult {
        guard isConfigured else {
            throw DemoAPIError.invalidBaseURL
        }

        let login = try await request(method: "POST", path: "/auth/login", backend: .auth)
        guard login.statusCode == 200 else {
            throw DemoAPIError.unexpectedStatus(login.statusCode, path: "/auth/login")
        }
        sessionState = DemoSessionState(userName: nil, token: "fresh-token")

        let me = try await decode(DemoUser.self, method: "GET", path: "/me", authorized: true)
        sessionState?.userName = me.name

        let firstFeed = try await request(method: "GET", path: "/feed", authorized: true)
        if firstFeed.statusCode == 401 {
            let refresh = try await request(method: "POST", path: "/auth/refresh", backend: .auth, authorized: true)
            guard refresh.statusCode == 200 else {
                throw DemoAPIError.unexpectedStatus(refresh.statusCode, path: "/auth/refresh")
            }
            sessionState?.token = "refreshed-token"
            let retriedFeed = try await decode(DemoFeed.self, method: "GET", path: "/feed", authorized: true)
            return DemoFlowResult(userName: me.name, feedMessage: retriedFeed.message)
        }

        guard firstFeed.statusCode == 200 else {
            throw DemoAPIError.unexpectedStatus(firstFeed.statusCode, path: "/feed")
        }

        let feed = try decoder.decode(DemoFeed.self, from: firstFeed.data)
        return DemoFlowResult(userName: me.name, feedMessage: feed.message)
    }

    func restoreSeededSession() async throws -> DemoBootstrapResult {
        guard isConfigured else {
            throw DemoAPIError.invalidBaseURL
        }
        guard sessionState != nil else {
            throw DemoAPIError.missingSeededSession
        }

        async let meResponse = request(method: "GET", path: "/me", authorized: true)
        async let notificationsResponse = request(method: "GET", path: "/notifications", authorized: true)
        let (me, notifications) = try await (meResponse, notificationsResponse)

        if me.statusCode == 401 || notifications.statusCode == 401 {
            sessionState = nil
            return .sessionExpired
        }

        guard me.statusCode == 200 else {
            throw DemoAPIError.unexpectedStatus(me.statusCode, path: "/me")
        }
        guard notifications.statusCode == 200 else {
            throw DemoAPIError.unexpectedStatus(notifications.statusCode, path: "/notifications")
        }

        let user = try decoder.decode(DemoUser.self, from: me.data)
        let feed = try decoder.decode(DemoFeed.self, from: notifications.data)
        sessionState?.userName = user.name
        return .feedReady(DemoFlowResult(userName: user.name, feedMessage: feed.message))
    }

    private var isConfigured: Bool {
        apiBaseURL.host != "invalid.wirestub.local" && authBaseURL.host != "invalid.wirestub.local"
    }

    private func decode<T: Decodable>(
        _ type: T.Type,
        method: String,
        path: String,
        backend: DemoBackend = .api,
        authorized: Bool = false
    ) async throws -> T {
        let response = try await request(method: method, path: path, backend: backend, authorized: authorized)
        guard response.statusCode == 200 else {
            throw DemoAPIError.unexpectedStatus(response.statusCode, path: path)
        }
        return try decoder.decode(T.self, from: response.data)
    }

    private func request(
        method: String,
        path: String,
        backend: DemoBackend = .api,
        authorized: Bool = false
    ) async throws -> (data: Data, statusCode: Int) {
        var request = URLRequest(url: endpoint(path, backend: backend))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if authorized, let token = sessionState?.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DemoAPIError.invalidResponse
        }
        return (data, httpResponse.statusCode)
    }

    private func endpoint(_ path: String, backend: DemoBackend) -> URL {
        let relativePath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        switch backend {
        case .api:
            return apiBaseURL.appendingPathComponent(relativePath)
        case .auth:
            return authBaseURL.appendingPathComponent(relativePath)
        }
    }

    private static func validBaseURL(named key: String, environment: [String: String]) -> URL? {
        let rawBaseURL = environment[key] ?? ""
        guard let components = URLComponents(string: rawBaseURL),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.host != nil,
              let baseURL = components.url else {
            return nil
        }
        return baseURL
    }
}
