import Foundation
import FlyingFox
import FlyingSocks
import WireStubCore

final class FlyingFoxHTTPServerAdapter: HTTPServerAdapter, @unchecked Sendable {
    private enum State {
        case stopped
        case starting
        case started
    }

    private let replayMode: ReplayMode
    private let lock = NSLock()
    private var server: HTTPServer?
    private var runTask: Task<Void, Error>?
    private var currentBaseURL: URL
    private var state: State = .stopped
    private var activeStartID: UUID?

    init(replayMode: ReplayMode) {
        self.replayMode = replayMode
        self.currentBaseURL = Self.loopbackURL()
    }

    var baseURL: URL {
        lock.withLock { currentBaseURL }
    }

    var isStarted: Bool {
        lock.withLock { state == .started }
    }

    func start(handler: @escaping @Sendable (RequestSnapshot) async -> StubResult) async throws {
        let startID = UUID()
        try lock.withLock {
            if self.state != .stopped {
                throw LocalStubServerError.alreadyStarted
            }
            self.state = .starting
            self.activeStartID = startID
        }

        var startedServer: HTTPServer?
        var startedTask: Task<Void, Error>?
        do {
            let address = try sockaddr_in.inet(ip4: "127.0.0.1", port: 0)
            let server = HTTPServer(address: address)
            startedServer = server
            await server.appendRoute("*", handler: { request in
                let snapshot = await ServerRequestAdapter.makeSnapshot(from: request, baseURL: self.baseURL)
                let result = await handler(snapshot)
                if let delay = ServerResponseAdapter.responseDelay(for: result) {
                    try? await Task.sleep(for: delay)
                }
                return ServerResponseAdapter.makeResponse(from: result, replayMode: self.replayMode)
            })

            let serverTask = Task {
                try await server.run()
            }
            startedTask = serverTask

            lock.withLock {
                self.server = server
                self.runTask = serverTask
            }

            try await server.waitUntilListening()
            let baseURL = try await makeBaseURL(from: server)
            let shouldFinalize = lock.withLock {
                self.state == .starting && self.activeStartID == startID && self.server === server
            }
            guard shouldFinalize else {
                if let startedServer {
                    await startedServer.stop(timeout: 0.1)
                }
                if let startedTask {
                    _ = await startedTask.result
                }
                lock.withLock {
                    self.server = nil
                    self.runTask = nil
                    self.currentBaseURL = Self.loopbackURL()
                    self.state = .stopped
                    self.activeStartID = nil
                }
                throw LocalStubServerError.notStarted
            }
            lock.withLock {
                self.currentBaseURL = baseURL
                self.state = .started
                self.activeStartID = nil
            }
        } catch {
            if let startedServer {
                await startedServer.stop(timeout: 0.1)
            }
            if let startedTask {
                _ = await startedTask.result
            }
            lock.withLock {
                self.server = nil
                self.runTask = nil
                self.currentBaseURL = Self.loopbackURL()
                self.state = .stopped
                self.activeStartID = nil
            }
            throw error
        }
    }

    func stop() async {
        let state: (HTTPServer, Task<Void, Error>)? = lock.withLock {
            guard let server, let runTask else { return nil }
            self.server = nil
            self.runTask = nil
            self.currentBaseURL = Self.loopbackURL()
            self.state = .stopped
            self.activeStartID = nil
            return (server, runTask)
        }

        guard let (server, runTask) = state else { return }
        await server.stop(timeout: 0.1)
        _ = await runTask.result
    }

    private func makeBaseURL(from server: HTTPServer) async throws -> URL {
        guard let address = await server.listeningAddress else {
            throw LocalStubServerError.invalidListeningAddress
        }

        if case .ip4(let host, port: let port) = address {
            return Self.loopbackURL(host: host, port: Int(port))
        }
        throw LocalStubServerError.invalidListeningAddress
    }

    private static func loopbackURL(
        scheme: String = "http",
        host: String = "127.0.0.1",
        port: Int = 0
    ) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = port
        guard let url = components.url else {
            preconditionFailure("Invalid loopback URL")
        }
        return url
    }
}
