# Stage 6 CLI Summary

## Commands implemented
- `wirestub inspect <file.har>`
- `wirestub validate <file.har>`
- `wirestub sanitize <input.har> <output.har> [options]`

## Options implemented
- `wirestub validate --strict <file.har>`
- `wirestub sanitize --remove-header <name>` (repeatable)
- `wirestub sanitize --redact-query <name>` (repeatable)
- `wirestub sanitize --redact-json-key <name>` (repeatable)

## Files changed
- `Package.swift`
- `Sources/WireStubCLI/CLICommandRunner.swift`
- `Sources/WireStubCLI/CommandIO.swift`
- `Sources/WireStubCLI/InspectCommand.swift`
- `Sources/WireStubCLI/ValidateCommand.swift`
- `Sources/WireStubCLI/SanitizeCommand.swift`
- `Sources/WireStubCLI/WireStubCLI.swift`
- `Sources/WireStubHAR/HARModels.swift`
- `Sources/WireStubHAR/HARValidation.swift`
- `Sources/WireStubHAR/HARSanitizer.swift`
- `Tests/WireStubCLITests/CLITestHelpers.swift`
- `Tests/WireStubCLITests/InspectCommandTests.swift`
- `Tests/WireStubCLITests/ValidateCommandTests.swift`
- `Tests/WireStubCLITests/SanitizeCommandTests.swift`
- `Tests/WireStubArchitectureTests/ModuleBoundaryTests.swift`
- `.gitignore`

## Tests added
- `InspectCommandTests`
  - `testInspectPrintsEntryCountMethodsAndPaths`
  - `testInspectDoesNotPrintSensitiveValues`
  - `testInspectFailsForMissingFile`
  - `testInspectFailsForMalformedHAR`
- `ValidateCommandTests`
  - `testValidatePassesForValidHAR`
  - `testValidateReportsSensitiveWarningsWithoutValues`
  - `testValidateStrictFailsOnWarnings`
  - `testValidateFailsForMalformedHAR`
- `SanitizeCommandTests`
  - `testSanitizeWritesLoadableHAR`
  - `testSanitizeRemovesAuthorizationCookieAndSetCookie`
  - `testSanitizeRedactsSensitiveQueryItems`
  - `testSanitizeRedactsSensitiveJSONKeys`
  - `testSanitizePreservesNonSensitiveEntries`
  - `testSanitizeDoesNotPrintSensitiveValues`
  - `testSanitizeDoesNotOverwriteInputByDefault`
- Architecture
  - `testWireStubCLIDoesNotImportServerURLProtocolOrXCTest`

## Example invocations
```bash
wirestub inspect Tests/WireStubHARTests/HARFixtures/simple_get.har
wirestub validate --strict Tests/WireStubHARTests/HARFixtures/sensitive_headers.har
wirestub sanitize Tests/WireStubHARTests/HARFixtures/sensitive_headers.har /tmp/sanitized.har
wirestub sanitize input.har output.har --remove-header X-Custom-Token --redact-query session --redact-json-key secret
```

## Exit code behavior
- `0`: command succeeded; `validate` warnings still exit `0` unless `--strict` is used.
- `1`: validation warnings became blocking under `--strict`.
- `65`: HAR data error or normalization failure.
- `66`: input HAR file not found.
- `73`: sanitize output could not be written or would overwrite the input path.

## Behavior before / after
- **Before:** `WireStubCLI` was scaffold-only and there was no tested command surface over HAR services.
- **After:** the executable is wired to `HARLoader`, `HARValidation`, `HARNormalizer`, and `HARSanitizer`, with redacted inspect/validate output and configurable sanitize options.

## Deferred CLI features
- No recording mode
- No proxy mode
- No localhost server runner
- No `sanitize --in-place`
- No `sanitize --fail-if-sensitive`
- No dedicated executable smoke test beyond the built CLI target and command-logic tests

## Final test state
- `swift test` passes with **226 tests, 0 failures**.
