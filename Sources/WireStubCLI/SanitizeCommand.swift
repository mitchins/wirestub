import ArgumentParser
import Foundation

struct SanitizeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sanitize",
        abstract: "Sanitize a HAR file."
    )

    @Option(name: .customLong("remove-header"), help: "Header name to remove. Repeatable.")
    var removeHeaders: [String] = []

    @Option(name: .customLong("redact-query"), help: "Query item name to redact. Repeatable.")
    var redactQueryItems: [String] = []

    @Option(name: .customLong("redact-json-key"), help: "JSON key to redact. Repeatable.")
    var redactJSONKeys: [String] = []

    @Argument(help: "Path to the input HAR file.")
    var input: String

    @Argument(help: "Path to the output HAR file.")
    var output: String

    func run() throws {
        let result = CLICommandRunner.sanitize(
            input: URL(fileURLWithPath: input),
            output: URL(fileURLWithPath: output),
            removeHeaders: removeHeaders,
            redactQueryItems: redactQueryItems,
            redactJSONKeys: redactJSONKeys
        )
        try CommandIO.write(result)
    }
}
