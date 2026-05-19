# Stage 8 CI Checklist

## Workflow present
- `.github/workflows/ci.yml` ✅

## Package checks
- `swift build` job present ✅
- `swift test` job present ✅

## Demo checks
- XcodeGen install step present ✅
- demo project generation step present ✅
- demo simulator test step present ✅

## Local validation performed
- `swift build` ✅
- `swift test` ✅
- `xcodegen generate` in `Demo/WireStubDemo` ✅
- `xcodebuild ... build-for-testing` for sample app ✅
- `xcodebuild ... test-without-building` for sample app ✅

## Notes
- CI targets `macos-15`
- Demo CI uses `platform=iOS Simulator,name=iPhone 16`
- The demo project is generated from `Demo/WireStubDemo/project.yml`
- The generated `.xcodeproj` is intentionally ignored
