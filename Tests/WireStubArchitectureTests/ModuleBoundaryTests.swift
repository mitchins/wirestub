import XCTest

/// Enforces hard module boundary rules by scanning source files for forbidden imports.
/// These tests must remain green from the first commit and serve as anti-drift gates.
final class ModuleBoundaryTests: XCTestCase {

    // MARK: - Helpers

    private func sourceFiles(under path: String) -> [URL] {
        let base = URL(fileURLWithPath: path)
        guard let enumerator = FileManager.default.enumerator(
            at: base,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    private func packageRoot() -> String {
        // Walk up from the test bundle to find Package.swift
        var url = URL(fileURLWithPath: #file)
        while url.path != "/" {
            url = url.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return url.path
            }
        }
        fatalError("Could not locate Package.swift from \(#file)")
    }

    private func assertNoForbiddenImports(
        in sourceDir: String,
        forbidden: [String],
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let root = packageRoot()
        let targetPath = "\(root)/Sources/\(sourceDir)"
        let files = sourceFiles(under: targetPath)

        var violations: [String] = []
        for fileURL in files {
            guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            for importName in forbidden {
                // Match `import <Module>` lines
                let lines = contents.components(separatedBy: "\n")
                for (idx, line) in lines.enumerated() {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    let tokens = trimmed.split(whereSeparator: { $0.isWhitespace })
                    if tokens.count >= 2, tokens[0] == "import", String(tokens[1]) == importName {
                        violations.append("\(fileURL.lastPathComponent):\(idx + 1): forbidden import '\(importName)'")
                    }
                }
            }
        }

        if !violations.isEmpty {
            XCTFail(
                "Module boundary violation in \(sourceDir):\n" + violations.joined(separator: "\n"),
                file: file,
                line: line
            )
        }
    }

    // MARK: - WireStubCore boundaries

    func testWireStubCoreSourcesDoNotImportXCTestHARServerOrURLProtocolModules() {
        assertNoForbiddenImports(
            in: "WireStubCore",
            forbidden: ["XCTest", "WireStubHAR", "WireStubServer", "WireStubURLProtocol", "WireStubXCTest"]
        )
    }

    // MARK: - WireStubHAR boundaries

    func testWireStubHARDoesNotImportServerURLProtocolOrXCTest() {
        assertNoForbiddenImports(
            in: "WireStubHAR",
            forbidden: ["WireStubServer", "WireStubURLProtocol", "WireStubXCTest", "XCTest"]
        )
    }

    // MARK: - WireStubServer boundaries

    func testWireStubServerDoesNotImportXCTest() {
        assertNoForbiddenImports(
            in: "WireStubServer",
            forbidden: ["XCTest", "WireStubXCTest"]
        )
    }

    func testWireStubServerDoesNotImportHAR() {
        assertNoForbiddenImports(
            in: "WireStubServer",
            forbidden: ["WireStubHAR"]
        )
    }

    // MARK: - WireStubURLProtocol boundaries

    func testWireStubURLProtocolDoesNotImportHAROrServer() {
        assertNoForbiddenImports(
            in: "WireStubURLProtocol",
            forbidden: ["WireStubHAR", "WireStubServer"]
        )
    }

    func testWireStubURLProtocolDoesNotImportXCTest() {
        assertNoForbiddenImports(
            in: "WireStubURLProtocol",
            forbidden: ["XCTest"]
        )
    }

    func testURLProtocolGlobalRegistrationIsNotUsedByServerMode() throws {
        let root = packageRoot()
        let files = sourceFiles(under: "\(root)/Sources/WireStubServer")
        let contents = try files.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")

        XCTAssertFalse(contents.contains("URLProtocol.registerClass"))
        XCTAssertFalse(contents.contains("URLProtocol.unregisterClass"))
    }

    // MARK: - WireStubCLI boundaries

    func testWireStubCLIDoesNotImportServerURLProtocolOrXCTest() {
        assertNoForbiddenImports(
            in: "WireStubCLI",
            forbidden: ["WireStubServer", "WireStubURLProtocol", "WireStubXCTest", "XCTest"]
        )
    }

    func testSampleAppDoesNotImportWireStubModules() throws {
        let root = packageRoot()
        let files = sourceFiles(under: "\(root)/Demo/WireStubDemo/WireStubDemo")
        let contents = try files.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")

        XCTAssertFalse(contents.contains("import WireStubCore"))
        XCTAssertFalse(contents.contains("import WireStubHAR"))
        XCTAssertFalse(contents.contains("import WireStubServer"))
        XCTAssertFalse(contents.contains("import WireStubURLProtocol"))
        XCTAssertFalse(contents.contains("import WireStubXCTest"))
    }
}
