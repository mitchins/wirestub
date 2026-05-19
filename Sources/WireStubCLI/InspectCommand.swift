import ArgumentParser
import Foundation

struct InspectCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "inspect",
        abstract: "Inspect a HAR file."
    )

    @Argument(help: "Path to the HAR file.")
    var file: String

    func run() throws {
        let result = CLICommandRunner.inspect(file: URL(fileURLWithPath: file))
        try CommandIO.write(result)
    }
}
