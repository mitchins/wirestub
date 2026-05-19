import Foundation

// MARK: - StubScenario

/// A complete replay scenario: an ordered list of routes plus replay configuration.
public struct StubScenario: Sendable {
    /// Optional scenario name used in diagnostics.
    public var name: String?
    /// Routes available to the replay engine.
    public var routes: [StubRoute]
    /// Unmatched-request behavior.
    public var mode: ReplayMode
    /// Route-consumption strategy.
    public var replayStrategy: ReplayStrategy
    /// Default matching policy inherited by routes whose matchers use scenario policy.
    public var matchingPolicy: MatchingPolicy

    /// Creates a replay scenario.
    public init(
        name: String? = nil,
        routes: [StubRoute],
        mode: ReplayMode = .strict,
        replayStrategy: ReplayStrategy = .firstMatch,
        matchingPolicy: MatchingPolicy = .defaultUIReplay
    ) {
        self.name = name
        self.routes = routes
        self.mode = mode
        self.replayStrategy = replayStrategy
        self.matchingPolicy = matchingPolicy
    }
}
