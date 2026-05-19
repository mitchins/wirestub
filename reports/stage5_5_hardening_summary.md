# Stage 5.5 Hardening Summary

## Scope
Focused hardening only. No CLI work, no new recording/proxy features, no product-center shift.

## Must-fix items

### 1. Redaction hardening
- **Before:** rendered diagnostics could leak sensitive values through mismatch reasons; journal output had no dedicated redacted rendering API.
- **After:** diagnostics use redacted mismatch rendering, request targets redact sensitive query values, and `RequestJournal.renderedTimeline()` provides a safe shared rendering path for diagnostics and XCTest failures.
- **Files changed:** `Sources/WireStubCore/Diagnostics.swift`, `Sources/WireStubCore/MatchResult.swift`, `Sources/WireStubCore/RequestJournal.swift`, `Sources/WireStubXCTest/LocalStubServer+WireStub.swift`
- **Tests added:** `testServerUnmatchedDiagnosticBodyRedactsAuthorizationCookieAndTokenQuery`, `testURLProtocolUnmatchedDiagnosticBodyRedactsSensitiveValues`, `testXCTestFailureMessagesRedactSensitiveValues`, `testHARValidationWarningsDoNotLeakSensitiveValues`, `testJournalRenderedTimelineRedactsSensitiveValues`

### 2. Duplicate-header crash fixes
- **Before:** HAR normalization and server request adaptation used duplicate-unsafe dictionary construction.
- **After:** duplicate headers are normalized deterministically through `HTTPHeaderUtilities.dictionary(from:)`, and sensitive duplicates are redacted safely.
- **Files changed:** `Sources/WireStubCore/RequestSnapshot.swift`, `Sources/WireStubServer/ServerRequestAdapter.swift`, `Sources/WireStubHAR/HARNormalizer.swift`
- **Tests added:** `testHARParserDoesNotCrashOnDuplicateHeaders`, `testServerRequestAdapterDoesNotCrashOnDuplicateHeaders`, `testHeaderMatchingIsCaseInsensitive`, `testRedactionAppliesToDuplicateSensitiveHeaders`

### 3. URLProtocol registry lifecycle cleanup
- **Before:** URLProtocol installations only returned `StubEngine`, with no cleanup handle for registry/token invalidation.
- **After:** installs return `URLProtocolInstallation`, which exposes `engine` and `invalidate()`, unregisters tokens, and supports scoped cleanup.
- **Files changed:** `Sources/WireStubURLProtocol/URLProtocolInstaller.swift`, `Tests/WireStubURLProtocolTests/URLProtocolTestHelpers.swift`, `Tests/WireStubURLProtocolTests/URLProtocolIsolationTests.swift`
- **Tests added:** `testURLProtocolInstallationCanBeInvalidated`, `testURLProtocolRegistryDoesNotRetainInvalidatedEngine`, `testURLProtocolStateDoesNotLeakAfterInvalidation`, `testSeparateURLProtocolInstallationsRemainIsolatedAfterCleanup`

### 4. Duplicate query-key semantics
- **Before:** `querySubset`/`queryExact` effectively collapsed duplicates via first-match lookup.
- **After:** matching consumes duplicate query items by multiplicity, preserving duplicate-aware subset/exact semantics; redacted rendering also redacts all duplicate sensitive query keys.
- **Files changed:** `Sources/WireStubCore/StubEngine.swift`, `Sources/WireStubCore/Diagnostics.swift`, `Sources/WireStubHAR/HARNormalizer.swift`
- **Tests added:** `testQueryExactDistinguishesDuplicateQueryItems`, `testQuerySubsetRequiresExpectedDuplicateQueryItems`, `testQuerySubsetAllowsAdditionalDuplicateQueryItems`, `testSensitiveQueryRedactionRedactsAllDuplicateTokenKeys`, `testHARImportPreservesDuplicateQueryItems`

### 5. `assertScenarioComplete()` semantics
- **Before:** completion was inferred by set membership, which was ambiguous for `firstMatch` and less explicit for repeated route IDs.
- **After:** ordered replay requires the exact ordered route-ID sequence to be consumed; `firstMatch` now throws a clear unsupported error.
- **Files changed:** `Sources/WireStubXCTest/LocalStubServer+WireStub.swift`, `Sources/WireStubXCTest/WireStubXCTestError.swift`
- **Tests added:** `testAssertScenarioCompletePassesWhenAllOrderedRoutesConsumed`, `testAssertScenarioCompleteFailsWhenOrderedRouteUnconsumed`, `testAssertScenarioCompleteTracksRepeatedIdenticalRoutesByRouteID`, `testAssertScenarioCompleteThrowsClearErrorForFirstMatch`, `testAssertScenarioCompleteHandlesSequenceRoutesDeterministically`

### 6. `StubResponse.delay` parity
- **Before:** URLProtocol honored delay, server mode ignored it.
- **After:** both adapters honor `StubResponse.delay` before delivering matched responses.
- **Files changed:** `Sources/WireStubServer/ServerResponseAdapter.swift`, `Sources/WireStubServer/FlyingFoxHTTPServerAdapter.swift`
- **Tests added:** `testServerHonorsStubResponseDelay`, `testURLProtocolHonorsStubResponseDelay`, `testCoreServerURLProtocolDelayParity`

### 7. `configure(app)` pre-start trap
- **Before:** `configure(app)` could inject `http://127.0.0.1:0` before start.
- **After:** `configure` is throwing and refuses to configure until the server is started with a real port.
- **Files changed:** `Sources/WireStubServer/LocalStubServer.swift`, `Sources/WireStubServer/HTTPServerAdapter.swift`, `Sources/WireStubXCTest/LocalStubServer+WireStub.swift`, `Sources/WireStubXCTest/WireStubXCTestError.swift`
- **Tests added:** `testConfigureAppBeforeServerStartThrowsUsefulError`, `testConfigureAppAfterServerStartInjectsRealPort`, `testConfigureAppNeverInjectsPortZero`

### 8. Async teardown cleanup in tests/server
- **Before:** several tests used `defer { Task { await stop() } }`, which did not await cleanup.
- **After:** tests use awaited teardown blocks; server adapter tracks explicit start state and resets loopback URL on stop. Start/stop lifecycle now has broader regression coverage.
- **Files changed:** `Sources/WireStubServer/FlyingFoxHTTPServerAdapter.swift`, `Tests/WireStubArchitectureTests/NoAppInjectionContractTests.swift`, `Tests/WireStubServerTests/LocalStubServerIsolationTests.swift`, `Tests/WireStubServerTests/LocalStubServerLifecycleTests.swift`
- **Tests added:** `testStartReturnsOnlyWhenServerAcceptsRequests`, `testStopAwaitsTeardownAndPortStopsAcceptingRequests`, `testStopIsIdempotent`, `testStartStopRepeatedlyDoesNotLeakPorts`, `testServerCanRestartOrThrowsPredictablyAfterStop`

### 9. Dead/silent public API cleanup
- **Before:** `StubScenario.matchingPolicy` did not affect matching, and `SensitiveHeaderPolicy.warn` did not surface structured normalization warnings.
- **After:** scenario matching policy is live for routes that use the scenario default, and HAR normalization has a structured primary API: `HARNormalizer.normalize(...) -> HARNormalizationResult`.
- **Files changed:** `Sources/WireStubCore/StubRoute.swift`, `Sources/WireStubCore/StubEngine.swift`, `Sources/WireStubHAR/HARModels.swift`, `Sources/WireStubHAR/HARValidation.swift`, `Sources/WireStubHAR/HARNormalizer.swift`
- **Tests added:** `testStubScenarioMatchingPolicyControlsMatching`, `testScenarioMatchingPolicyCanRequireCanonicalJSONBodyHash`, `testScenarioMatchingPolicyCanUseHeaderSubsetWhenOptedIn`, `testSensitiveHeaderPolicyWarnProducesStructuredWarnings`, `testSensitiveHeaderPolicyWarnWarningsDoNotLeakValues`, `testSensitiveHeaderPolicyStripRemovesSensitiveHeaders`, `testSensitiveHeaderPolicyFailThrows`

## Files changed
- Core: `RequestSnapshot.swift`, `StubRoute.swift`, `StubEngine.swift`, `MatchResult.swift`, `Diagnostics.swift`
- Server: `HTTPServerAdapter.swift`, `LocalStubServer.swift`, `ServerRequestAdapter.swift`, `ServerResponseAdapter.swift`, `FlyingFoxHTTPServerAdapter.swift`
- URLProtocol: `URLProtocolInstaller.swift`
- HAR: `HARModels.swift`, `HARValidation.swift`, `HARNormalizer.swift`
- XCTest: `LocalStubServer+WireStub.swift`, `WireStubXCTestError.swift`
- Tests: updated across Core, HAR, Server, URLProtocol, XCTest support, and architecture suites
- Repo hygiene: `.gitignore`

## Tests added
- Added 41 regression tests across Core, HAR, Server, URLProtocol, and XCTest support.
- `swift test` now passes with **210 tests, 0 failures**.

## Behavior before / after
- **Before:** architecture was sound but hardening gaps remained around redaction, duplicate-header/query correctness, URLProtocol cleanup, completion semantics, and pre-start configuration.
- **After:** those must-fix behaviors are covered by regression tests and enforced in the live code paths used by server, URLProtocol, HAR normalization, and XCTest support.

## Deferred concerns
- `StubResponse.text(_:encoding:)` still accepts arbitrary encodings while defaulting the content type to UTF-8; this was not part of the Stage 5.5 must-fix list.
- URLProtocol/server parity for percent-encoded path edge cases remains worth targeted review, but was not part of the required hardening gate.
- The public journal still stores raw request snapshots internally; Stage 5.5 added redacted rendering APIs and routed user-facing output through them.
