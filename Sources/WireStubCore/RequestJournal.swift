import Foundation

// MARK: - JournalEntry

/// A single handled request recorded in the engine journal.
public struct JournalEntry: Sendable {
    /// Match outcome for a journaled request.
    public enum Outcome: Sendable {
        case matched(routeID: String, status: Int)
        case unmatched(UnmatchedRequestDiagnostic)
    }

    /// Zero-based arrival order in the journal.
    public let sequenceIndex: Int
    /// Captured request snapshot.
    public let request: RequestSnapshot
    /// Timestamp when the entry was recorded.
    public let timestamp: Date
    /// Whether the request matched a route or produced an unmatched diagnostic.
    public let outcome: Outcome
}

// MARK: - RequestJournal

/// Ordered, append-only record of all requests handled by the engine.
public struct RequestJournal: Sendable {
    public private(set) var entries: [JournalEntry]

    /// Creates an empty request journal.
    public init() {
        self.entries = []
    }

    mutating func append(_ entry: JournalEntry) {
        entries.append(entry)
    }

    // MARK: - Querying

    /// Returns all journal entries matching a method/path pair.
    public func entries(method: String, path: String) -> [JournalEntry] {
        entries.filter {
            $0.request.method.uppercased() == method.uppercased() &&
            $0.request.path == path
        }
    }

    /// Returns the number of journal entries matching a method/path pair.
    public func count(method: String, path: String) -> Int {
        entries(method: method, path: path).count
    }

    /// All unmatched journal entries.
    public var unmatchedEntries: [JournalEntry] {
        entries.filter {
            if case .unmatched = $0.outcome { return true }
            return false
        }
    }

    /// All matched journal entries.
    public var matchedEntries: [JournalEntry] {
        entries.filter {
            if case .matched = $0.outcome { return true }
            return false
        }
    }
}
