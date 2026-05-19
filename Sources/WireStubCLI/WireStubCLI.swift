import ArgumentParser

@main
struct WireStubCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "wirestub",
        abstract: "HAR inspection, validation, and sanitization tools for WireStub.",
        subcommands: [
            InspectCommand.self,
            ValidateCommand.self,
            SanitizeCommand.self,
        ]
    )
}
