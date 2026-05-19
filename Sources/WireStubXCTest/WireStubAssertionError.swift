import Foundation

/// Error thrown by XCTest-facing WireStub assertion helpers.
public struct WireStubAssertionError: Error, LocalizedError, Sendable {
    /// Assertion failure message.
    public let message: String

    /// Creates an assertion error with a human-readable message.
    public init(_ message: String) {
        self.message = message
    }

    /// Human-readable error description.
    public var errorDescription: String? { message }
}
