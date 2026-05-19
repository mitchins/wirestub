# Stage 8 Public API Audit

## Verdict
**Acceptable for public release at v0.1.0**

The public API exposes the intended product shape without leaking backend or registry implementation details.

## Audit checklist

### No accidental implementation types exposed
- No FlyingFox types are public ✅
- URLProtocol registry internals remain non-public ✅
- Server adapter protocol remains internal and explicitly marked `internal` ✅

### Public products are named cleanly
- `WireStubCore` ✅
- `WireStubHAR` ✅
- `WireStubServer` ✅
- `WireStubURLProtocol` ✅
- `WireStubXCTest` ✅
- `wirestub` executable ✅

### Lifecycle / semantics docs present
- `LocalStubServer` lifecycle documented ✅
- `URLProtocolInstallation.invalidate()` documented ✅
- `configure(app)` throwing behavior documented ✅
- `assertScenarioComplete()` ordered-only behavior documented ✅
- `StubScenario.matchingPolicy` behavior documented ✅
- HAR sanitize/validate caveat documented ✅

## Notable API characteristics

### Intentionally mutable configuration structs
These remain public and mutable:
- `StubScenario`
- `RouteMatcher`
- `StubRoute`
- `HARImportOptions`
- `HARSanitizationOptions`

This is acceptable for v0.1.0 because they are configuration values, while runtime state remains isolated inside `StubEngine`, `LocalStubServer`, and `URLProtocolInstallation`.

### Concurrency surfaces
- `LocalStubServer` is `@unchecked Sendable`
- `URLProtocolInstallation` is `@unchecked Sendable`

This is acceptable because both are runtime handles over mutable state, and the public docs now frame them as lifecycle-managed handles rather than plain values.

## No public API leaks found
- No FlyingFox backend API in public surface ✅
- No URLProtocol token registry API exposed ✅
- No sample-app dependency on WireStub in the app target ✅
- No local absolute paths in package or demo config ✅

## Release notes
- The generated demo `.xcodeproj` is intentionally not source-of-truth.
- `Demo/WireStubDemo/project.yml` is the maintained project definition.
