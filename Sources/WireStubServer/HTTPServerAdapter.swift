import Foundation
import WireStubCore

internal protocol HTTPServerAdapter: Sendable {
    var baseURL: URL { get }
    var isStarted: Bool { get }
    func start(handler: @escaping @Sendable (RequestSnapshot) async -> StubResult) async throws
    func stop() async
}

/// Errors surfaced by `LocalStubServer` lifecycle management.
public enum LocalStubServerError: Error, Equatable {
    case alreadyStarted
    case invalidListeningAddress
    case notStarted
}

extension NSLock {
    @inlinable
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
