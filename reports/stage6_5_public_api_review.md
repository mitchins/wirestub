# Stage 6.5 Public API Review

## Executive summary
The public API is coherent for the current product shape, with a clear split between:

- `WireStubCore` for replay semantics
- `WireStubServer` for localhost replay
- `WireStubURLProtocol` for in-process replay
- `WireStubHAR` for input material and CLI plumbing
- `WireStubXCTest` for launch configuration and assertions

No accidental public leakage of server internals, HAR runtime types into Core, or CLI-only dependencies was found.

## Findings

### P2: Many public value types expose mutable stored properties
**Area:** Core + HAR models  
**Examples:** `StubScenario`, `RouteMatcher`, `StubRoute`, `HARImportOptions`, `HARSanitizationOptions`  
**Why it matters:** Consumers can mutate configuration values freely after construction, which is convenient but means the API relies on documentation rather than immutability for correctness cues.  
**Verdict:** Acceptable for V1 because engine state is actor-owned and separate from these configuration values.

### P2: `@unchecked Sendable` appears on lifecycle surfaces
**Area:** `LocalStubServer`, `URLProtocolInstallation`  
**Why it matters:** These types wrap mutable runtime state and locks, so callers should treat them as lifecycle handles, not plain values.  
**Verdict:** Acceptable with documentation. This pass added lifecycle and invalidation docs.

### P3: `SensitiveHeaderPolicy` name is narrower than the behavior users may infer
**Area:** HAR normalization  
**Why it matters:** The type controls header behavior, while related validation/sanitization also cover query items and JSON keys. The name is not wrong, but it is narrower than the overall secret-handling surface.  
**Verdict:** Document, do not rename now.

### P3: `StubResponse.text(_:encoding:)` always writes a UTF-8 content type
**Area:** Core convenience API  
**Why it matters:** A caller can pass a non-UTF-8 encoding while the default content type still says `charset=utf-8`.  
**Verdict:** Existing deferred concern; document rather than rewrite in this pass.

### P3: CLI command logic is intentionally internal
**Area:** CLI  
**Why it matters:** `CLICommandRunner` and result types are internal-only, which is correct for the executable target but means examples should show the `wirestub` binary, not internal Swift APIs.  
**Verdict:** Good boundary; README uses binary examples only.

## Docs readiness updates made in this pass
- Documented `LocalStubServer` lifecycle and `baseURL`/`isStarted` expectations.
- Documented `URLProtocolInstallation.invalidate()` and configuration-scoped installation.
- Documented `HARSanitizer`, `HARSanitizationOptions`, and the fact that sanitized HARs may still validate with warnings on sensitive field names.
- Added a full `README.md` covering tested usage examples and current limitations.

## API ergonomics verdict
**Good enough for release at current scope.**

The API supports the intended product shape without pushing users toward global state, app-side imports, or transport-specific replay logic. The main remaining needs are documentation and examples rather than runtime redesign.
