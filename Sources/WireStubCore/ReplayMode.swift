import Foundation

// MARK: - ReplayMode

/// Controls how unmatched requests are surfaced by the replay engine.
public enum ReplayMode: Sendable, Equatable {
    /// Unmatched requests return a diagnostic error response. No external network.
    case strict
    /// Unmatched requests return a synthetic response with the given status. No external network.
    case permissive(status: Int)
}

// MARK: - ReplayStrategy

/// Controls whether replay consumes routes in order or searches for the first match.
public enum ReplayStrategy: Sendable, Equatable {
    /// Routes are consumed in definition order. The engine advances the cursor only on a successful match.
    case ordered
    /// Every request matches against all routes; the first match wins.
    case firstMatch
}

// MARK: - SequenceExhaustion

/// Controls behavior when a response sequence has no remaining entries.
public enum SequenceExhaustion: Sendable, Equatable {
    /// Returns the last response in the sequence for all subsequent requests.
    case repeatLast
    /// Treats further requests as unmatched after the sequence is exhausted. Default.
    case fail
}

// MARK: - ResponseProvider

/// Source of responses for a route.
public enum ResponseProvider: Sendable {
    case staticResponse(StubResponse)
    case sequence([StubResponse], exhaustion: SequenceExhaustion)
}

extension ResponseProvider: Equatable {
    public static func == (lhs: ResponseProvider, rhs: ResponseProvider) -> Bool {
        switch (lhs, rhs) {
        case (.staticResponse(let a), .staticResponse(let b)):
            return a == b
        case (.sequence(let a, let ea), .sequence(let b, let eb)):
            return a == b && ea == eb
        default:
            return false
        }
    }
}
