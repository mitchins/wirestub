# Contributing

Thanks for contributing to WireStub.

## Before opening a PR

1. Keep the product shape intact:
   - localhost server for UI tests is the primary path
   - URLProtocol remains an adapter over the same core engine
   - HAR stays input material, not the runtime model
2. Avoid adding new runtime surface area without tests and docs.
3. Sanitize HAR fixtures before committing them.

## Local checks

```bash
swift build
swift test
```

For the simulator demo:

```bash
cd Demo/WireStubDemo
xcodegen generate
cd ../..
xcodebuild -project Demo/WireStubDemo/WireStubDemo.xcodeproj -scheme WireStubDemo -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' test
```

## Design guardrails

- Do not expose server backend implementation details publicly.
- Do not add global route registries or app-side WireStub imports.
- Preserve redaction in diagnostics, validation output, and docs.
