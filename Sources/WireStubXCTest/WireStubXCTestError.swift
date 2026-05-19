import Foundation
import WireStubCore

/// Errors surfaced by XCTest-facing helper APIs.
public enum WireStubXCTestError: Error, LocalizedError, Equatable {
    case serverNotStarted
    case scenarioCompletionUnsupported(replayStrategy: ReplayStrategy)

    /// Human-readable XCTest helper error description.
    public var errorDescription: String? {
        switch self {
        case .serverNotStarted:
            return "WireStub server must be started before configuring an app."
        case .scenarioCompletionUnsupported(let replayStrategy):
            return "Scenario completion is not meaningful for \(replayStrategy) replay."
        }
    }
}
