# Stage 8 Release Hardening Summary

## Outcome
WireStub is hardened for an initial public Swift package release at the current feature scope.

## Final validation
- `swift build` ✅
- `swift test` ✅
- Package test result: **227 tests, 0 failures**
- Demo project regenerated with XcodeGen ✅
- Demo app build for iOS Simulator ✅
- Demo UI tests ✅

## Release hardening completed

### Public API and docs
- Added inline documentation comments across the public API surface.
- Documented:
  - `StubScenario.matchingPolicy` as live scenario-default matching behavior
  - `URLProtocolInstallation.invalidate()`
  - `LocalStubServer` lifecycle
  - throwing `configure(app)` behavior
  - ordered-only `assertScenarioComplete()`
  - HAR sanitize/validate caveat: sanitized HARs may still preserve sensitive-looking field names with redacted values

### Repository metadata
- Added `LICENSE` (MIT)
- Added `CHANGELOG.md` for `0.1.0`
- Added lightweight `CONTRIBUTING.md`
- Added `SECURITY.md` focused on HAR secret handling

### CI
- Added GitHub Actions workflow at `.github/workflows/ci.yml`
- CI now covers:
  - `swift build`
  - `swift test`
  - demo project generation via XcodeGen
  - demo simulator test run

### README / release docs
- Installation example now uses `from: "0.1.0"`
- Sample app instructions now include `xcodegen generate`
- README examples were reviewed against the current API surface

### Demo / packaging sanity
- Demo deployment target now matches package support floor semantics better (`iOS 16.0`)
- Generated `.xcodeproj` is now treated as generated output via `.gitignore`
- Sample app continues to avoid WireStub imports
- Demo project uses only relative paths (`path: ../..`)

### Reports policy
- `reports/` remains ignored by default with an explicit allowlist for checked-in milestone reports.
- This policy is intentional and preserved.

## Review passes

### Adversarial review
A final release-focused adversarial review surfaced four issues and all were addressed:
1. CI only built the demo instead of running its UI tests
2. Generated `.xcodeproj` should be treated as generated output
3. Demo deployment target was higher than the package floor
4. `HTTPServerAdapter` visibility was implicit instead of explicit

### CodeRabbit
`coderabbit doctor` / `coderabbit review --plain` were attempted during Stage 8, but the command did not produce usable output before hanging. No CodeRabbit findings were available to incorporate in the final reports.

## No scope creep
No new runtime features were added. This pass stayed within release hardening, documentation, CI, and packaging sanity.
