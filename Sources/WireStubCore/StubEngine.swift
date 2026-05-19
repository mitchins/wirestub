import Foundation

// MARK: - StubResult

/// Result returned by the replay engine for a handled request.
public enum StubResult: Sendable {
    case matched(StubResponse, routeID: String)
    case unmatched(UnmatchedRequestDiagnostic)
}

// MARK: - RouteEvaluator

/// Evaluates a single route matcher against an incoming request snapshot.
enum RouteEvaluator {

    static func evaluate(
        route: StubRoute,
        against request: RequestSnapshot,
        scenarioPolicy: MatchingPolicy
    ) -> MatchEvaluation {
        let policy = route.matcher.usesScenarioMatchingPolicy ? scenarioPolicy : route.matcher.policy
        var reasons: [MismatchReason] = []

        for component in policy.components {
            switch component {
            case .method:
                if route.matcher.method.uppercased() != request.method.uppercased() {
                    reasons.append(.methodMismatch(
                        expected: route.matcher.method,
                        received: request.method
                    ))
                }

            case .path:
                if route.matcher.path != request.path {
                    reasons.append(.pathMismatch(
                        expected: route.matcher.path,
                        received: request.path
                    ))
                }

            case .headerSubset:
                for (name, expectedValue) in route.matcher.headers {
                    let loweredName = name.lowercased()
                    guard !policy.ignoredHeaders.contains(loweredName) else { continue }
                    let receivedValue = HTTPHeaderUtilities.value(named: name, in: request.headers)
                    if receivedValue != expectedValue {
                        reasons.append(.headerMismatch(name: name, expected: expectedValue, received: receivedValue))
                    }
                }

            case .querySubset:
                var remainingRequestItems = filteredQueryItems(request.queryItems, policy: policy)
                for item in filteredQueryItems(route.matcher.queryItems, policy: policy) {
                    if let index = remainingRequestItems.firstIndex(of: item) {
                        remainingRequestItems.remove(at: index)
                    } else {
                        reasons.append(.missingQueryItem(name: item.name, expectedValue: item.value))
                    }
                }

            case .queryExact:
                let routeItems = filteredQueryItems(route.matcher.queryItems, policy: policy)
                var remainingRequestItems = filteredQueryItems(request.queryItems, policy: policy)
                for item in routeItems {
                    if let index = remainingRequestItems.firstIndex(of: item) {
                        remainingRequestItems.remove(at: index)
                    } else {
                        reasons.append(.missingQueryItem(name: item.name, expectedValue: item.value))
                    }
                }
                for item in remainingRequestItems {
                    reasons.append(.extraQueryItem(name: item.name))
                }

            case .bodyHash:
                let routeHash = route.matcher.body.map { BodyCanonicalizer.rawHash($0) } ?? ""
                let requestHash = request.body.map { BodyCanonicalizer.rawHash($0) } ?? ""
                if routeHash != requestHash {
                    reasons.append(.bodyHashMismatch(expected: routeHash, received: requestHash))
                }

            case .canonicalJSONBodyHash:
                let routeData = route.matcher.body ?? Data()
                let requestData = request.body ?? Data()

                let routeResult = BodyCanonicalizer.canonicalJSONHash(routeData, fallbackSide: .route)
                let requestResult = BodyCanonicalizer.canonicalJSONHash(requestData, fallbackSide: .request)

                let routeFailed = routeResult.canonicalizationFailed
                let requestFailed = requestResult.canonicalizationFailed
                if routeFailed || requestFailed {
                    let side: CanonicalFailureSide = routeFailed && requestFailed ? .both
                        : routeFailed ? .route : .request
                    let reason = [routeResult.failureReason, requestResult.failureReason]
                        .compactMap { $0 }.joined(separator: "; ")
                    reasons.append(.canonicalizationFailed(side: side, underlying: reason))
                }

                if routeResult.hash != requestResult.hash {
                    let mismatch: MismatchReason
                    if routeFailed || requestFailed {
                        mismatch = .bodyHashMismatch(
                            expected: routeResult.hash,
                            received: requestResult.hash
                        )
                    } else {
                        mismatch = .canonicalJSONBodyHashMismatch(
                            expected: routeResult.hash,
                            received: requestResult.hash
                        )
                    }
                    reasons.append(mismatch)
                }
            }
        }

        return reasons.isEmpty
            ? .match(routeID: route.id)
            : .mismatch(routeID: route.id, reasons: reasons)
    }

    private static func filteredQueryItems(_ items: [QueryItem], policy: MatchingPolicy) -> [QueryItem] {
        items.filter { !policy.ignoredQueryItems.contains($0.name.lowercased()) }
    }
}

// MARK: - StubEngine

/// Transport-agnostic replay engine. Actor-isolated for safe concurrent access.
public actor StubEngine {
    /// Replay mode inherited from the scenario used to create this engine.
    public nonisolated let replayMode: ReplayMode
    private let scenario: StubScenario
    private var sequenceIndices: [String: Int] = [:]
    private var orderedCursor: Int = 0
    private var journal: RequestJournal = RequestJournal()

    /// Creates a replay engine for a scenario.
    public init(scenario: StubScenario) {
        self.replayMode = scenario.mode
        self.scenario = scenario
    }

    /// Handles a single request snapshot and returns a matched or unmatched result.
    public func handle(_ request: RequestSnapshot) async -> StubResult {
        let index = journal.entries.count
        let timestamp = Date()

        let result = resolveResult(for: request)

        let entry = JournalEntry(
            sequenceIndex: index,
            request: request,
            timestamp: timestamp,
            outcome: outcomeFor(result: result)
        )
        journal.append(entry)
        return result
    }

    /// Returns the current immutable request journal.
    public func currentJournal() -> RequestJournal {
        journal
    }

    private func resolveResult(for request: RequestSnapshot) -> StubResult {
        switch scenario.replayStrategy {
        case .firstMatch:
            return resolveFirstMatch(for: request)
        case .ordered:
            return resolveOrdered(for: request)
        }
    }

    private func resolveFirstMatch(for request: RequestSnapshot) -> StubResult {
        var allEvaluations: [MatchEvaluation] = []

        for route in scenario.routes {
            let evaluation = RouteEvaluator.evaluate(route: route, against: request, scenarioPolicy: scenario.matchingPolicy)
            if evaluation.isMatch {
                if let response = nextResponse(from: route) {
                    return .matched(response, routeID: route.id)
                } else {
                    allEvaluations.append(
                        .mismatch(routeID: route.id, reasons: [.sequenceExhausted(routeID: route.id)])
                    )
                }
            } else {
                allEvaluations.append(evaluation)
            }
        }

        return unmatched(request: request, candidates: allEvaluations, nextExpected: nil)
    }

    private func resolveOrdered(for request: RequestSnapshot) -> StubResult {
        guard orderedCursor < scenario.routes.count else {
            return unmatched(request: request, candidates: [], nextExpected: nil)
        }

        let expectedRoute = scenario.routes[orderedCursor]
        let evaluation = RouteEvaluator.evaluate(route: expectedRoute, against: request, scenarioPolicy: scenario.matchingPolicy)

        if evaluation.isMatch {
            if let response = nextResponse(from: expectedRoute) {
                orderedCursor += 1
                return .matched(response, routeID: expectedRoute.id)
            } else {
                return unmatched(
                    request: request,
                    candidates: [.mismatch(routeID: expectedRoute.id, reasons: [.sequenceExhausted(routeID: expectedRoute.id)])],
                    nextExpected: expectedRoute.id
                )
            }
        }

        let closestCandidates: [MatchEvaluation] = scenario.routes.map {
            RouteEvaluator.evaluate(route: $0, against: request, scenarioPolicy: scenario.matchingPolicy)
        }.sorted { lhs, rhs in
            lhs.reasons.count < rhs.reasons.count
        }

        return unmatched(
            request: request,
            candidates: [evaluation] + closestCandidates.filter { $0.routeID != expectedRoute.id },
            nextExpected: expectedRoute.id
        )
    }

    private func nextResponse(from route: StubRoute) -> StubResponse? {
        switch route.responseProvider {
        case .staticResponse(let response):
            return response

        case .sequence(let responses, let exhaustion):
            let idx = sequenceIndices[route.id, default: 0]
            if idx < responses.count {
                sequenceIndices[route.id] = idx + 1
                return responses[idx]
            }
            switch exhaustion {
            case .repeatLast:
                return responses.last
            case .fail:
                return nil
            }
        }
    }

    private func unmatched(
        request: RequestSnapshot,
        candidates: [MatchEvaluation],
        nextExpected: String?
    ) -> StubResult {
        let diagnostic = UnmatchedRequestDiagnostic(
            request: request,
            scenarioName: scenario.name,
            replayStrategy: scenario.replayStrategy,
            closestCandidates: candidates,
            nextExpectedRouteID: nextExpected,
            requestsReceivedSoFar: journal.entries
        )
        return .unmatched(diagnostic)
    }

    private func outcomeFor(result: StubResult) -> JournalEntry.Outcome {
        switch result {
        case .matched(let response, let routeID):
            return .matched(routeID: routeID, status: response.status)
        case .unmatched(let diagnostic):
            return .unmatched(diagnostic)
        }
    }
}
