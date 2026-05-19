import Foundation

enum CLITestHelpers {
    static func fixtureURL(_ name: String, file: StaticString = #filePath) -> URL {
        let fileURL = URL(fileURLWithPath: String(describing: file))
        return fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("WireStubHARTests")
            .appendingPathComponent("HARFixtures")
            .appendingPathComponent(name)
    }

    static func temporaryDirectory(testName: String = UUID().uuidString) throws -> URL {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("WireStubCLITests").appendingPathComponent(testName)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
}
