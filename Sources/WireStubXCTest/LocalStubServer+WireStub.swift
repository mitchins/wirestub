import Foundation
import WireStubCore
import WireStubServer

private enum WireStubAssertionPolling {
    static let timeout: Duration = .seconds(5)
    static let pollInterval: Duration = .milliseconds(100)
    static let stabilityWindow: Duration = .milliseconds(250)

    struct StableJournalCondition {
        let waitingFor: String
        let isSatisfied: (RequestJournal) -> Bool
        let timeoutMessage: (RequestJournal) -> String
    }
}

/// XCTest-facing launch configuration and assertion helpers for `LocalStubServer`.
public extension LocalStubServer {
    /// Injects the started server's base URL into an app launch environment.
    ///
    /// This throws if the server has not been started yet; it never injects a placeholder port.
    func configure(_ app: WireStubLaunchConfigurable, baseURLEnvironmentKey: String = "API_BASE_URL") throws {
        guard isStarted, let port = baseURL.port, port != 0 else {
            throw WireStubXCTestError.serverNotStarted
        }
        app.launchEnvironment[baseURLEnvironmentKey] = baseURL.absoluteString
    }

    /// Injects the started server's base URL into multiple launch environment keys.
    func configure(_ app: WireStubLaunchConfigurable, baseURLEnvironmentKeys: [String]) throws {
        guard isStarted, let port = baseURL.port, port != 0 else {
            throw WireStubXCTestError.serverNotStarted
        }
        for key in baseURLEnvironmentKeys {
            app.launchEnvironment[key] = baseURL.absoluteString
        }
    }

    /// Asserts that at least one request matching the expectation was recorded.
    func assertReceived(_ expectation: RequestExpectation) async throws {
        let journal = await journal()
        guard journal.count(matching: expectation) > 0 else {
            throw WireStubAssertionError(
                "Expected request to be received: \(expectation)\n\nRequests received:\n\(journal.renderedTimeline())"
            )
        }
    }

    /// Asserts that the request expectation was recorded exactly `expectedCount` times.
    func assertReceived(_ expectation: RequestExpectation, count expectedCount: Int) async throws {
        let journal = await journal()
        let actualCount = journal.count(matching: expectation)
        guard actualCount == expectedCount else {
            throw WireStubAssertionError(
                "Expected \(expectedCount) occurrences of \(expectation), actual \(actualCount)\n\nRequests received:\n\(journal.renderedTimeline())"
            )
        }
    }

    /// Asserts that a matching request was never recorded.
    func assertNeverReceived(_ expectation: RequestExpectation) async throws {
        let journal = await journal()
        let actualCount = journal.count(matching: expectation)
        guard actualCount == 0 else {
            throw WireStubAssertionError(
                "Expected request never to occur: \(expectation)\nActual count: \(actualCount)\n\nRequests received:\n\(journal.renderedTimeline())"
            )
        }
    }

    /// Asserts that the recorded request sequence exactly matches the provided expectations.
    func assertReceivedSequence(_ expectations: [RequestExpectation]) async throws {
        let journal = await journal()
        let matches = journal.matchesSequence(expectations)
        guard matches else {
            let expectedDescription = expectations.map(\.description).joined(separator: "\n")
            let actualDescription = journal.entries.map { $0.request.renderedTarget(redacted: true) }.joined(separator: "\n")
            throw WireStubAssertionError(
                "Expected sequence:\n\(expectedDescription)\n\nActual timeline:\n\(actualDescription.isEmpty ? "<empty>" : actualDescription)\n\nRequests received:\n\(journal.renderedTimeline())"
            )
        }
    }

    /// Asserts that no unmatched requests were recorded.
    func assertNoUnmatchedRequests() async throws {
        let journal = await journal()
        let unmatchedDiagnostics = journal.unmatchedEntries.compactMap { entry -> String? in
            guard case .unmatched(let diagnostic) = entry.outcome else { return nil }
            return diagnostic.render()
        }
        guard unmatchedDiagnostics.isEmpty else {
            throw WireStubAssertionError(
                "Expected no unmatched requests.\n\n" + unmatchedDiagnostics.joined(separator: "\n\n")
            )
        }
    }

    /// Alias for `assertNoUnmatchedRequests()`.
    func assertNoUnexpectedRequests() async throws {
        try await assertNoUnmatchedRequests()
    }

    /// Polls until at least one matching request has been recorded.
    func assertEventuallyReceived(
        _ expectation: RequestExpectation,
        timeout: Duration = .seconds(5),
        pollInterval: Duration = .milliseconds(100)
    ) async throws {
        try await pollAssertion(
            waitingFor: "request to be received: \(expectation)",
            timeout: timeout,
            pollInterval: pollInterval
        ) {
            try await self.assertReceived(expectation)
        }
    }

    /// Polls until the matching request has been recorded exactly `expectedCount` times and the journal has settled.
    func assertEventuallyReceived(
        _ expectation: RequestExpectation,
        count expectedCount: Int,
        timeout: Duration = .seconds(5),
        pollInterval: Duration = .milliseconds(100)
    ) async throws {
        let condition = WireStubAssertionPolling.StableJournalCondition(
            waitingFor: "\(expectedCount) occurrences of \(expectation)",
            isSatisfied: { journal in
                journal.count(matching: expectation) == expectedCount
            },
            timeoutMessage: { journal in
                "Expected \(expectedCount) occurrences of \(expectation), actual \(journal.count(matching: expectation))\n\nRequests received:\n\(journal.renderedTimeline())"
            }
        )
        try await pollStableJournalAssertion(
            condition: condition,
            timeout: timeout,
            pollInterval: pollInterval,
            assertion: {
            try await self.assertReceived(expectation, count: expectedCount)
            }
        )
    }

    /// Polls until the recorded request sequence exactly matches the provided expectations and the journal has settled.
    func assertEventuallyReceivedSequence(
        _ expectations: [RequestExpectation],
        timeout: Duration = .seconds(5),
        pollInterval: Duration = .milliseconds(100)
    ) async throws {
        let condition = WireStubAssertionPolling.StableJournalCondition(
            waitingFor: "request sequence to be received",
            isSatisfied: { journal in journal.matchesSequence(expectations) },
            timeoutMessage: { journal in
                let expectedDescription = expectations.map(\.description).joined(separator: "\n")
                let actualDescription = journal.entries.map { $0.request.renderedTarget(redacted: true) }.joined(separator: "\n")
                return "Expected sequence:\n\(expectedDescription)\n\nActual timeline:\n\(actualDescription.isEmpty ? "<empty>" : actualDescription)\n\nRequests received:\n\(journal.renderedTimeline())"
            }
        )
        try await pollStableJournalAssertion(
            condition: condition,
            timeout: timeout,
            pollInterval: pollInterval,
            assertion: {
            try await self.assertReceivedSequence(expectations)
            }
        )
    }

    /// Polls until no unmatched requests have been recorded and the journal has settled.
    ///
    /// The stability check avoids passing immediately while an XCUI-driven app is still producing startup traffic.
    func assertEventuallyNoUnmatchedRequests(
        timeout: Duration = .seconds(5),
        pollInterval: Duration = .milliseconds(100)
    ) async throws {
        let condition = WireStubAssertionPolling.StableJournalCondition(
            waitingFor: "no unmatched requests",
            isSatisfied: { journal in
                journal.unmatchedEntries.isEmpty
            },
            timeoutMessage: { journal in
                "Expected no unmatched requests after the journal settled.\n\nRequests received:\n\(journal.renderedTimeline())"
            }
        )
        try await pollStableJournalAssertion(
            condition: condition,
            timeout: timeout,
            pollInterval: pollInterval,
            assertion: {
            try await self.assertNoUnmatchedRequests()
            }
        )
    }

    /// Alias for `assertEventuallyNoUnmatchedRequests()`.
    func assertEventuallyNoUnexpectedRequests(
        timeout: Duration = .seconds(5),
        pollInterval: Duration = .milliseconds(100)
    ) async throws {
        try await assertEventuallyNoUnmatchedRequests(timeout: timeout, pollInterval: pollInterval)
    }

    /// Polls until an ordered-replay scenario has fully consumed its route list.
    func assertEventuallyScenarioComplete(
        timeout: Duration = .seconds(5),
        pollInterval: Duration = .milliseconds(100)
    ) async throws {
        try await pollAssertion(
            waitingFor: "scenario completion",
            timeout: timeout,
            pollInterval: pollInterval
        ) {
            try await self.assertScenarioComplete()
        }
    }

    /// Asserts that an ordered-replay scenario has fully consumed its route list.
    ///
    /// This is intentionally ordered-only; for `.firstMatch` replay it throws
    /// `WireStubXCTestError.scenarioCompletionUnsupported`.
    func assertScenarioComplete() async throws {
        guard scenario.replayStrategy == .ordered else {
            throw WireStubXCTestError.scenarioCompletionUnsupported(replayStrategy: scenario.replayStrategy)
        }

        let journal = await journal()
        let consumedRouteIDs = journal.matchedEntries.compactMap { entry -> String? in
            guard case .matched(let routeID, _) = entry.outcome else { return nil }
            return routeID
        }
        let expectedRouteIDs = scenario.routes.map(\.id)
        guard consumedRouteIDs == expectedRouteIDs else {
            let missing = expectedRouteIDs.filter { !consumedRouteIDs.contains($0) }
            let extra = consumedRouteIDs.filter { !expectedRouteIDs.contains($0) }
            throw WireStubAssertionError(
                "Expected scenario to be complete.\nExpected route IDs: \(expectedRouteIDs.joined(separator: ", "))\nActual route IDs: \(consumedRouteIDs.joined(separator: ", "))\nMissing route IDs: \(missing.joined(separator: ", "))\nExtra route IDs: \(extra.joined(separator: ", "))\n\nRequests received:\n\(journal.renderedTimeline())"
            )
        }
    }

    /// Asserts that a route identifier appeared in matched journal entries.
    func assertRouteConsumed(_ routeID: String) async throws {
        let journal = await journal()
        let consumed = journal.matchedEntries.contains { entry in
            if case .matched(let matchedID, _) = entry.outcome { return matchedID == routeID }
            return false
        }
        guard consumed else {
            throw WireStubAssertionError(
                "Expected route to be consumed: \(routeID)\n\nRequests received:\n\(journal.renderedTimeline())"
            )
        }
    }

    /// Asserts that a route identifier did not appear in matched journal entries.
    func assertRouteNotConsumed(_ routeID: String) async throws {
        let journal = await journal()
        let consumed = journal.matchedEntries.contains { entry in
            if case .matched(let matchedID, _) = entry.outcome { return matchedID == routeID }
            return false
        }
        guard !consumed else {
            throw WireStubAssertionError(
                "Expected route not to be consumed: \(routeID)\n\nRequests received:\n\(journal.renderedTimeline())"
            )
        }
    }
}

private extension LocalStubServer {
    func pollAssertion(
        waitingFor description: String,
        timeout: Duration,
        pollInterval: Duration,
        assertion: @escaping () async throws -> Void
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        var lastAssertionError: WireStubAssertionError?

        while true {
            do {
                try await assertion()
                return
            } catch let error as WireStubAssertionError {
                lastAssertionError = error
            } catch {
                throw error
            }

            if clock.now >= deadline {
                throw timedOut(waitingFor: description, timeout: timeout, message: lastAssertionError?.message ?? "Assertion did not succeed.")
            }
            try await Task.sleep(for: pollInterval)
        }
    }

    func pollStableJournalAssertion(
        condition: WireStubAssertionPolling.StableJournalCondition,
        timeout: Duration,
        pollInterval: Duration,
        assertion: @escaping () async throws -> Void
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        var lastAssertionError: WireStubAssertionError?
        var lastObservedCount: Int?
        var lastJournalChange = clock.now

        while true {
            let currentJournal = await journal()
            let now = clock.now

            if lastObservedCount != currentJournal.entries.count {
                lastObservedCount = currentJournal.entries.count
                lastJournalChange = now
            }

            do {
                try await assertion()
                lastAssertionError = nil
                let refreshedJournal = await journal()
                let refreshedNow = clock.now
                if lastObservedCount != refreshedJournal.entries.count {
                    lastObservedCount = refreshedJournal.entries.count
                    lastJournalChange = refreshedNow
                }

                if condition.isSatisfied(refreshedJournal),
                   refreshedNow >= lastJournalChange.advanced(by: WireStubAssertionPolling.stabilityWindow) {
                    return
                }
            } catch let error as WireStubAssertionError {
                lastAssertionError = error
            } catch {
                throw error
            }

            if clock.now >= deadline {
                let timeoutJournal = await journal()
                let message = lastAssertionError?.message ?? condition.timeoutMessage(timeoutJournal)
                throw timedOut(waitingFor: condition.waitingFor, timeout: timeout, message: message)
            }
            try await Task.sleep(for: pollInterval)
        }
    }

    func timedOut(waitingFor description: String, timeout: Duration, message: String) -> WireStubAssertionError {
        WireStubAssertionError("Timed out after \(timeout) waiting for \(description).\n\n\(message)")
    }
}

private extension RequestJournal {
    func entries(matching expectation: RequestExpectation) -> [JournalEntry] {
        entries.filter { expectation.matches($0.request) }
    }

    func count(matching expectation: RequestExpectation) -> Int {
        entries(matching: expectation).count
    }

    func matchesSequence(_ expectations: [RequestExpectation]) -> Bool {
        guard entries.count == expectations.count else { return false }
        return zip(expectations, entries).allSatisfy { expected, entry in
            expected.matches(entry.request)
        }
    }
}
