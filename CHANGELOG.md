# Changelog

All notable changes to this project will be documented in this file.

## [0.1.0] - 2026-05-18

### Added
- `WireStubCore` deterministic replay engine with ordered and first-match replay
- `WireStubServer` localhost HTTP adapter for UI tests
- `WireStubHAR` loader, validator, normalizer, and sanitizer
- `WireStubURLProtocol` in-process adapter for unit/integration tests
- `WireStubXCTest` launch configuration and assertion helpers
- `wirestub` CLI with `inspect`, `validate`, and `sanitize`
- Simulator sample app and XCUITest demo under `Demo/WireStubDemo`

### Hardened
- Redacted diagnostics and CLI output for sensitive HAR values
- Duplicate-safe header and query handling
- Scoped URLProtocol installation invalidation
- Structured HAR warnings and sanitization summaries
