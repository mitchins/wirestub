import ArgumentParser
import Foundation

enum CommandIO {
    static func write(_ result: CLICommandResult) throws {
        if !result.stdout.isEmpty {
            print(result.stdout)
        }
        if !result.stderr.isEmpty {
            FileHandle.standardError.write(Data((result.stderr + "\n").utf8))
        }
        if result.exitCode != 0 {
            throw ExitCode(Int32(result.exitCode))
        }
    }
}
