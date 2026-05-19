import Foundation
import WireStubCore

/// A localhost replay server that adapts HTTP requests into `RequestSnapshot` values for a shared `StubEngine`.
///
/// Lifecycle:
/// - Create the server with a `StubScenario`.
/// - Call `start()` before reading `baseURL` or configuring an app under test.
/// - Use `stop()` during teardown; repeated stops are safe.
/// - `baseURL` resets to the placeholder loopback URL after stop and should only be treated as usable while `isStarted` is true.
public final class LocalStubServer: @unchecked Sendable {
    private let engine: StubEngine
    private let adapter: HTTPServerAdapter
    /// Scenario used to create the server and underlying replay engine.
    public let scenario: StubScenario

    /// The currently bound base URL.
    ///
    /// This is only a real listening address after `start()` succeeds.
    public var baseURL: URL {
        adapter.baseURL
    }

    /// Whether the adapter is currently started and ready to accept requests.
    public var isStarted: Bool {
        adapter.isStarted
    }

    /// Creates a localhost stub server for a scenario.
    public init(scenario: StubScenario) throws {
        self.scenario = scenario
        self.engine = StubEngine(scenario: scenario)
        self.adapter = FlyingFoxHTTPServerAdapter(replayMode: scenario.mode)
    }

    /// Starts listening on localhost and does not return until the adapter is ready.
    public func start() async throws {
        try await adapter.start { [engine] snapshot in
            await engine.handle(snapshot)
        }
    }

    /// Stops the server and waits for teardown to complete.
    public func stop() async {
        await adapter.stop()
    }

    /// Returns the current request journal captured by the shared replay engine.
    public func journal() async -> RequestJournal {
        await engine.currentJournal()
    }
}
