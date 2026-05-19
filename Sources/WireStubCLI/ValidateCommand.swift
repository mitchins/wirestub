import ArgumentParser
import Foundation

struct ValidateCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "validate",
        abstract: "Validate a HAR file."
    )

    @Flag(name: .long, help: "Treat warnings as validation failures.")
    var strict = false

    @Argument(help: "Path to the HAR file.")
    var file: String

    func run() throws {
        let result = CLICommandRunner.validate(file: URL(fileURLWithPath: file), strict: strict)
        try CommandIO.write(result)
    }
}
