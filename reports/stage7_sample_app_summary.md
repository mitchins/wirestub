# Stage 7 Sample App Summary

## Outcome
Implemented a real iOS sample app and XCUITest demo under `Demo/WireStubDemo` proving WireStub's primary product shape:

`StubScenario/HAR -> LocalStubServer -> XCUIApplication base URL injection -> app talks to localhost -> journal/assertions`

## What was added
- `Demo/WireStubDemo/project.yml`
- Generated `Demo/WireStubDemo/WireStubDemo.xcodeproj`
- SwiftUI sample app:
  - `WireStubDemoApp.swift`
  - `ContentView.swift`
  - `DemoViewModel.swift`
  - `DemoAPIClient.swift`
- UI tests:
  - `WireStubDemoUITests/WireStubDemoUITests.swift`
- HAR fixture:
  - `Demo/WireStubDemo/Fixtures/login_expire_refresh.har`
- Package architecture guard:
  - `testSampleAppDoesNotImportWireStubModules`
- README sample-app section with exact commands

## Demo flow covered
1. Logged-out screen
2. Tap **Log In**
3. `POST /auth/login`
4. `GET /me`
5. `GET /feed`
6. `401` on feed triggers `POST /auth/refresh`
7. Retry `GET /feed`
8. UI shows feed success

## Demo scenarios
- **Inline scenario** using `StubScenario`
- **HAR-backed scenario** using `HARLoader` + `HARNormalizer`

## Commands run

### Package validation
```bash
swift test
swift build
```

### Sample project generation
```bash
cd Demo/WireStubDemo
xcodegen generate
```

### Sample simulator build
```bash
xcodebuild \
  -project Demo/WireStubDemo/WireStubDemo.xcodeproj \
  -scheme WireStubDemo \
  -destination 'id=28425279-095C-4D48-B328-748935D117DD' \
  -derivedDataPath /tmp/WireStubDemoDerivedData \
  build-for-testing
```

### Sample UI test execution
```bash
xcodebuild \
  -project Demo/WireStubDemo/WireStubDemo.xcodeproj \
  -scheme WireStubDemo \
  -destination 'id=28425279-095C-4D48-B328-748935D117DD' \
  -derivedDataPath /tmp/WireStubDemoDerivedData \
  test-without-building
```

## Results
- Package `swift test` still passes
- Sample app builds for iOS Simulator
- XCUITest demo runs successfully
- App target does not import WireStub
- Test target imports WireStub and owns the replay server lifecycle

## Notes
- The sample intentionally keeps app logic boring and transport-real.
- No new WireStub runtime features were added.
- The sample targets simulator + localhost only for V1.
