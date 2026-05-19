# WireStub

WireStub is a deterministic network replay harness for Swift and iOS tests.

At its center is a transport-agnostic replay engine:

```text
HTTP server request -> RequestSnapshot -> StubEngine -> StubResponse
URLProtocol request  -> RequestSnapshot -> StubEngine -> StubResponse
```

The localhost server path is the primary product wedge for UI tests. The URLProtocol adapter exists for in-process unit and integration tests.

## What WireStub is

- A deterministic localhost HTTP server for XCUITest and UI-driven integration tests
- A shared replay engine that can also run through `URLProtocol`
- A HAR import, validation, and sanitization toolchain
- A request journal and assertion layer for test verification

## What WireStub is not

- Not a recorder or proxy
- Not a server-runner CLI
- Not a MITM/HTTPS interception tool
- Not a WebSocket or SSE replay harness
- Not “just another URLProtocol mock”

## Installation

```swift
.package(url: "https://github.com/mitchins/wirestub.git", from: "0.1.0")
```

Products:

- `WireStubCore`
- `WireStubHAR`
- `WireStubServer`
- `WireStubURLProtocol`
- `WireStubXCTest`
- `wirestub` executable

## UI test server replay example

```swift
import XCTest
import WireStubCore
import WireStubServer
import WireStubXCTest

final class LoginUITests: XCTestCase {
    func testLoginExpiresThenRefreshes() async throws {
        let scenario = StubScenario(
            routes: [
                .post("/auth/login", response: .status(200)),
                .get("/me", response: try .json(["id": 1, "name": "Blob"])),
                .get("/feed", response: .status(401)),
                .post("/auth/refresh", response: .status(200)),
                .get("/feed", response: try .json(["message": "Feed loaded"]))
            ],
            mode: .strict,
            replayStrategy: .ordered
        )

        let wire = try LocalStubServer(scenario: scenario)
        try await wire.start()
        addTeardownBlock { [wire] in
            await wire.stop()
        }

        let app = XCUIApplication()
        try wire.configure(app, baseURLEnvironmentKeys: ["API_BASE_URL", "AUTH_BASE_URL"])
        app.launch()

        // Drive the UI here.

        try await wire.assertEventuallyReceivedSequence([
            .post("/auth/login"),
            .get("/me"),
            .get("/feed"),
            .post("/auth/refresh"),
            .get("/feed")
        ])
        try await wire.assertEventuallyNoUnmatchedRequests()
        try await wire.assertEventuallyScenarioComplete()
    }
}
```

## Inline stub example

```swift
import WireStubCore

let scenario = StubScenario(
    routes: [
        .get("/users", matching: .init(id: "load-users"), response: try .json([
            ["id": 1, "name": "Blob"]
        ])),
        try .post(
            "/auth/refresh",
            matching: .init(
                id: "refresh-failed",
                headers: ["Authorization": "Bearer stale-token"]
            ),
            jsonBody: ["refreshToken": "stale-token"],
            response: .status(401)
        )
    ],
    mode: .strict,
    replayStrategy: .firstMatch
)
```

## HAR replay example

```swift
import WireStubHAR
import WireStubServer

let archive = try HARLoader.load(from: URL(fileURLWithPath: "Fixtures/login.har"))
let normalized = try HARNormalizer.normalize(
    archive,
    name: "login.har"
)

for warning in normalized.warnings {
    print("HAR warning: \(warning.message)")
}

let wire = try LocalStubServer(scenario: normalized.scenario)
try await wire.start()
```

## XCTest assertion example

```swift
try await wire.assertReceived(.post("/auth/login"))
try await wire.assertReceived(.get("/feed"), count: 2)
try await wire.assertNeverReceived(.delete("/account"))
try await wire.assertNoUnmatchedRequests()

try await wire.assertEventuallyReceived(.get("/notifications"))
try await wire.assertEventuallyReceived(.get("/notifications"), count: 1)
try await wire.assertEventuallyReceivedSequence([
    .post("/auth/login"),
    .get("/me"),
    .get("/feed")
])
try await wire.assertEventuallyNoUnmatchedRequests()
try await wire.assertEventuallyScenarioComplete()
```

`assertScenarioComplete()` is meaningful for ordered replay. For `firstMatch`, it throws a clear unsupported error.

## Concurrent startup traffic and replay strategy

Use replay strategy to match the app shape you actually have:

- Use `.ordered` when the app intentionally serializes requests and the exact order is part of the behavior under test.
- Use `.firstMatch` when launch, home, or auth-expiry traffic can happen in parallel and you care about **which** requests happened more than their exact interleaving.
- For stale-session or auth-expiry XCUI flows, `.firstMatch` plus `assertEventuallyReceived(...)`, `assertEventuallyReceived(..., count:)`, and `assertEventuallyNoUnmatchedRequests()` is usually the most stable setup.

If your app fires startup requests concurrently, avoid asserting a full request sequence unless the product behavior truly guarantees that order.

## App bootstrap boundary

WireStub owns the fake network world. It does **not** seed your app's auth/session state.

- WireStub starts the localhost server.
- WireStub injects base URLs into launch environment.
- Your **app or demo app** still owns any bootstrap hook used to launch “already authenticated” or “stale token” scenarios.

That boundary is intentional: the app target stays WireStub-free and only reads launch environment or other app-native bootstrap inputs.

## Auth-expiry / stale-session recipe

```swift
let scenario = StubScenario(
    name: "stale-session-expiry",
    routes: [
        .get(
            "/me",
            matching: .init(
                id: "bootstrap-me",
                headers: ["Authorization": "Bearer stale-token"]
            ),
            response: try .json(["id": 1, "name": "Blob"])
        ),
        .get(
            "/notifications",
            matching: .init(
                id: "bootstrap-notifications",
                headers: ["Authorization": "Bearer stale-token"]
            ),
            response: .status(401)
        ),
    ],
    mode: .strict,
    replayStrategy: .firstMatch
)

let wire = try LocalStubServer(scenario: scenario)
try await wire.start()
defer { await wire.stop() }

let app = XCUIApplication()
app.launchEnvironment["DEMO_BOOTSTRAP_STATE"] = "authenticated-stale" // Consumer-owned bootstrap hook
try wire.configure(app, baseURLEnvironmentKeys: ["API_BASE_URL", "AUTH_BASE_URL"])
app.launch()

try await wire.assertEventuallyReceived(.get("/me", headers: ["Authorization": "Bearer stale-token"]))
try await wire.assertEventuallyReceived(.get("/notifications", headers: ["Authorization": "Bearer stale-token"]))
try await wire.assertEventuallyNoUnmatchedRequests()
```

The demo app uses a consumer-owned launch-environment seed to model “cached user + stale token on launch.” Your app can use whatever bootstrap seam it already owns.

## Multi-base-url injection

If your app splits auth and API traffic across different environment keys, point both at the same stub server in XCUI:

```swift
let app = XCUIApplication()
try wire.configure(app, baseURLEnvironmentKeys: ["API_BASE_URL", "AUTH_BASE_URL"])
```

This is useful when multiple backends or service clients should all resolve to the same deterministic localhost replay server during the test.

## URLProtocol unit test example

```swift
import Foundation
import WireStubCore
import WireStubURLProtocol

let scenario = StubScenario(
    routes: [
        .get("/profile", response: try .json(["name": "Blob"]))
    ]
)

let configuration = URLSessionConfiguration.ephemeral
let installation = URLProtocolInstaller.install(scenario: scenario, into: configuration)
defer { installation.invalidate() }

let session = URLSession(configuration: configuration)
let url = URL(string: "https://example.test/profile")!
let (data, response) = try await session.data(from: url)

print((response as? HTTPURLResponse)?.statusCode ?? 0)
print(String(decoding: data, as: UTF8.self))
```

`URLProtocolInstaller` is configuration-scoped by design. Always keep the returned `URLProtocolInstallation` and call `invalidate()` during teardown.

## CLI examples

```bash
wirestub inspect Tests/WireStubHARTests/HARFixtures/simple_get.har
wirestub validate Tests/WireStubHARTests/HARFixtures/simple_get.har
wirestub validate --strict Tests/WireStubHARTests/HARFixtures/sensitive_headers.har
wirestub sanitize Tests/WireStubHARTests/HARFixtures/sensitive_headers.har /tmp/sanitized.har
wirestub sanitize input.har output.har --remove-header X-Session --redact-query session --redact-json-key password
```

`inspect` prints summary data only. `validate` reports warnings without secret values. `sanitize` removes or redacts sensitive values and writes a loadable HAR; validation may still report sensitive field names because the structure is preserved intentionally.

## Sample app

A real simulator-backed demo lives under `Demo/WireStubDemo`.

- The **app target does not import WireStub**
- The **XCUITest target imports WireStub** and owns the fake network world
- The app reads `API_BASE_URL` and `AUTH_BASE_URL` from launch environment and makes real HTTP calls to `127.0.0.1:<port>`
- The demo includes both an **inline scenario** and a **HAR-backed scenario** for the login -> refresh -> retry flow
- The demo also includes a **consumer-owned stale-session bootstrap** example that expires to a logged-out UI without the app importing WireStub

Run the sample UI tests from the repository root:

```bash
cd Demo/WireStubDemo
xcodegen generate
cd ../..

xcodebuild \
  -project Demo/WireStubDemo/WireStubDemo.xcodeproj \
  -scheme WireStubDemo \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,OS=18.2,name=iPhone 16' \
  test
```

If you need to regenerate the sample project from the XcodeGen spec:

```bash
cd Demo/WireStubDemo
xcodegen generate
```

This demo is **simulator/localhost only** in V1.

## Security note: HAR secrets

HAR files often contain live credentials, cookies, tokens, and passwords. Treat them as secrets:

- run `wirestub validate` before committing fixtures
- prefer `wirestub sanitize` before sharing HAR files
- do not assume third-party HAR exports are safe to check in
- WireStub redacts rendered diagnostics, but source HAR files can still contain raw secrets until sanitized

## Current limitations

- No recording or proxy mode
- No server-runner CLI mode
- No WebSocket or SSE replay
- No HTTPS MITM or physical-device interception
- No app-side injection requirement beyond a configurable base URL
- `assertScenarioComplete()` is ordered-replay only
- Eventual assertions still need a meaningful product-level “done” signal from your UI test before you decide the flow is complete
- `wirestub sanitize` does not support in-place overwrite in V1
 
