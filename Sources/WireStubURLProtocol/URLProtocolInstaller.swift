import Foundation
import WireStubCore

enum URLProtocolInternal {
    static let tokenHeader = "X-WireStub-Session-Token"
}

final class URLProtocolEngineRegistry: @unchecked Sendable {
    static let shared = URLProtocolEngineRegistry()

    struct Entry {
        let engine: StubEngine
        let replayMode: ReplayMode
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    func register(engine: StubEngine, replayMode: ReplayMode) -> String {
        let token = UUID().uuidString
        lock.lock()
        entries[token] = Entry(engine: engine, replayMode: replayMode)
        lock.unlock()
        return token
    }

    func entry(for token: String) -> Entry? {
        lock.lock()
        defer { lock.unlock() }
        return entries[token]
    }

    func unregister(_ token: String) {
        lock.lock()
        entries.removeValue(forKey: token)
        lock.unlock()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }
}

/// A scoped URLProtocol installation handle tied to a specific `URLSessionConfiguration`.
public final class URLProtocolInstallation: @unchecked Sendable {
    /// Engine used for requests sent through the installed configuration.
    public let engine: StubEngine

    private weak var configuration: URLSessionConfiguration?
    private let token: String
    private let lock = NSLock()
    private var invalidated = false

    init(engine: StubEngine, configuration: URLSessionConfiguration, token: String) {
        self.engine = engine
        self.configuration = configuration
        self.token = token
    }

    deinit {
        invalidate()
    }

    /// Unregisters the installation token and removes the private session header from the configuration.
    ///
    /// Call this during test teardown to prevent state leakage between URL sessions and tests.
    public func invalidate() {
        let tokenToRemove: String? = lock.withLock {
            guard !invalidated else { return nil }
            invalidated = true
            return token
        }

        guard let tokenToRemove else { return }
        URLProtocolEngineRegistry.shared.unregister(tokenToRemove)
        removeTokenHeader(from: configuration)
    }

    private func removeTokenHeader(from configuration: URLSessionConfiguration?) {
        guard let configuration else { return }
        var headers = configuration.httpAdditionalHeaders ?? [:]
        if let key = headers.keys.first(where: {
            String(describing: $0).caseInsensitiveCompare(URLProtocolInternal.tokenHeader) == .orderedSame
        }) {
            headers.removeValue(forKey: key)
        }
        configuration.httpAdditionalHeaders = headers
    }
}

/// Installs the WireStub URLProtocol adapter into a specific `URLSessionConfiguration`.
public enum URLProtocolInstaller {
    /// Installs a fresh engine for `scenario` into a specific `URLSessionConfiguration`.
    ///
    /// The returned installation must be invalidated during teardown to unregister its private token.
    public static func install(
        scenario: StubScenario,
        into configuration: URLSessionConfiguration
    ) -> URLProtocolInstallation {
        let engine = StubEngine(scenario: scenario)
        return install(engine: engine, into: configuration)
    }

    /// Installs an existing engine into a specific `URLSessionConfiguration`.
    ///
    /// This is the preferred in-process test path. It avoids global `URLProtocol` registration and scopes replay state
    /// to the provided configuration.
    public static func install(
        engine: StubEngine,
        into configuration: URLSessionConfiguration
    ) -> URLProtocolInstallation {
        let headers = configuration.httpAdditionalHeaders ?? [:]
        if let previousToken = token(in: headers) {
            URLProtocolEngineRegistry.shared.unregister(previousToken)
        }

        let token = URLProtocolEngineRegistry.shared.register(engine: engine, replayMode: engine.replayMode)
        var updatedHeaders = headers
        removeTokenHeader(from: &updatedHeaders)
        updatedHeaders[URLProtocolInternal.tokenHeader] = token
        configuration.httpAdditionalHeaders = updatedHeaders

        var protocolClasses = configuration.protocolClasses ?? []
        protocolClasses.removeAll { $0 == WireStubURLProtocol.self }
        protocolClasses.insert(WireStubURLProtocol.self, at: 0)
        configuration.protocolClasses = protocolClasses

        return URLProtocolInstallation(engine: engine, configuration: configuration, token: token)
    }

    private static func token(in headers: [AnyHashable: Any]) -> String? {
        headers.first { key, _ in
            String(describing: key).caseInsensitiveCompare(URLProtocolInternal.tokenHeader) == .orderedSame
        }?.value as? String
    }

    private static func removeTokenHeader(from headers: inout [AnyHashable: Any]) {
        if let key = headers.keys.first(where: {
            String(describing: $0).caseInsensitiveCompare(URLProtocolInternal.tokenHeader) == .orderedSame
        }) {
            headers.removeValue(forKey: key)
        }
    }
}
