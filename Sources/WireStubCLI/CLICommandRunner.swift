import Foundation
import WireStubHAR

struct CLICommandResult: Equatable {
    var stdout: String
    var stderr: String
    var exitCode: Int
}

private enum CLIExitCode: Int {
    case success = 0
    case validationFailure = 1
    case dataError = 65
    case noInput = 66
    case cantCreate = 73
}

private enum CLIError: LocalizedError {
    case fileNotFound(URL)
    case invalidHAR(String)
    case cannotWrite(URL)
    case refusingToOverwriteInput

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "HAR file not found: \(url.path)"
        case .invalidHAR(let message):
            return message
        case .cannotWrite(let url):
            return "Could not write output HAR: \(url.path)"
        case .refusingToOverwriteInput:
            return "Refusing to overwrite input HAR. Choose a different output path."
        }
    }

    var exitCode: CLIExitCode {
        switch self {
        case .fileNotFound:
            return .noInput
        case .invalidHAR:
            return .dataError
        case .cannotWrite, .refusingToOverwriteInput:
            return .cantCreate
        }
    }
}

enum CLICommandRunner {
    static func inspect(file: URL) -> CLICommandResult {
        do {
            let archive = try loadArchive(from: file)
            let report = HARValidation.validate(archive)
            let repeated = repeatedEndpoints(in: report.methodsAndPaths)
            let contentTypes = contentTypes(in: archive)
            let statusCodes = Set(archive.entries.map(\.response.status)).sorted()
            let hasSensitiveData = report.warnings.contains(where: isSensitiveWarning)

            var lines: [String] = []
            lines.append("Entry count: \(archive.entries.count)")
            lines.append("Requests:")
            lines.append(contentsOf: bulleted(report.methodsAndPaths))
            lines.append("Status codes: \(list(statusCodes.map(String.init), empty: "none"))")
            lines.append("Content types: \(list(contentTypes, empty: "none"))")
            lines.append("Repeated endpoints:")
            if repeated.isEmpty {
                lines.append("- none")
            } else {
                lines.append(contentsOf: repeated.map { "- \($0.key) (\($0.count)x)" })
            }
            lines.append("Sensitive data detected: \(hasSensitiveData ? "yes" : "no")")
            return CLICommandResult(stdout: lines.joined(separator: "\n"), stderr: "", exitCode: CLIExitCode.success.rawValue)
        } catch let error as CLIError {
            return failure(error)
        } catch {
            return failure(.invalidHAR("Could not inspect HAR file"))
        }
    }

    static func validate(file: URL, strict: Bool) -> CLICommandResult {
        do {
            let archive = try loadArchive(from: file)
            let report = HARValidation.validate(archive)
            let normalizedWarnings = report.warnings.map(humanizeWarning)
            let normalizationErrors = normalizationErrors(in: archive)
            let unsupportedWarnings = normalizedWarnings.filter(isUnsupportedWarning)
            let sensitiveWarnings = normalizedWarnings.filter(isSensitiveWarning)
            let generalWarnings = normalizedWarnings.filter { !isUnsupportedWarning($0) && !isSensitiveWarning($0) }

            var lines: [String] = []
            lines.append("Entry count: \(report.entryCount)")
            lines.append("Requests:")
            lines.append(contentsOf: bulleted(report.methodsAndPaths))
            lines.append("Warnings: \(generalWarnings.isEmpty ? "none" : "")")
            if !generalWarnings.isEmpty {
                lines.append(contentsOf: bulleted(generalWarnings))
            }
            lines.append("Unsupported entries: \(unsupportedWarnings.isEmpty ? "none" : "")")
            if !unsupportedWarnings.isEmpty {
                lines.append(contentsOf: bulleted(unsupportedWarnings))
            }
            lines.append("Sensitive data warnings: \(sensitiveWarnings.isEmpty ? "none" : "")")
            if !sensitiveWarnings.isEmpty {
                lines.append(contentsOf: bulleted(sensitiveWarnings))
            }
            if !normalizationErrors.isEmpty {
                lines.append("Errors:")
                lines.append(contentsOf: bulleted(normalizationErrors))
            }

            let exitCode: CLIExitCode
            if !normalizationErrors.isEmpty {
                exitCode = .dataError
            } else if strict && !normalizedWarnings.isEmpty {
                exitCode = .validationFailure
            } else {
                exitCode = .success
            }

            return CLICommandResult(stdout: lines.joined(separator: "\n"), stderr: "", exitCode: exitCode.rawValue)
        } catch let error as CLIError {
            return failure(error)
        } catch {
            return failure(.invalidHAR("Could not validate HAR file"))
        }
    }

    static func sanitize(
        input: URL,
        output: URL,
        removeHeaders: [String],
        redactQueryItems: [String],
        redactJSONKeys: [String]
    ) -> CLICommandResult {
        do {
            let inputURL = normalizedFileURL(input)
            let outputURL = normalizedFileURL(output)
            guard inputURL != outputURL else {
                throw CLIError.refusingToOverwriteInput
            }

            let archive = try loadArchive(from: inputURL)
            let options = HARSanitizationOptions(
                removeHeaders: HARSanitizationOptions.standard.removeHeaders.union(removeHeaders.map { $0.lowercased() }),
                redactQueryItems: HARSanitizationOptions.standard.redactQueryItems.union(redactQueryItems.map { $0.lowercased() }),
                redactJSONKeys: HARSanitizationOptions.standard.redactJSONKeys.union(redactJSONKeys.map { $0.lowercased() })
            )
            let result = HARSanitizer.sanitize(archive, options: options)
            let data = try HARSanitizer.data(from: result.archive)
            try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            do {
                try data.write(to: outputURL, options: .atomic)
            } catch {
                throw CLIError.cannotWrite(outputURL)
            }

            let lines = [
                "Sanitized entries: \(result.archive.entries.count)",
                "Removed request headers: \(result.summary.removedRequestHeaders)",
                "Removed response headers: \(result.summary.removedResponseHeaders)",
                "Redacted query items: \(result.summary.redactedQueryItems)",
                "Redacted JSON values: \(result.summary.redactedJSONValues)",
                "Output: \(outputURL.path)",
            ]
            return CLICommandResult(stdout: lines.joined(separator: "\n"), stderr: "", exitCode: CLIExitCode.success.rawValue)
        } catch let error as CLIError {
            return failure(error)
        } catch {
            return failure(.invalidHAR("Could not sanitize HAR file"))
        }
    }

    private static func loadArchive(from url: URL) throws -> HARArchive {
        let normalizedURL = normalizedFileURL(url)
        guard FileManager.default.fileExists(atPath: normalizedURL.path) else {
            throw CLIError.fileNotFound(normalizedURL)
        }
        do {
            return try HARLoader.load(from: normalizedURL)
        } catch let error as HARLoaderError {
            throw CLIError.invalidHAR(error.errorDescription ?? "HAR file is invalid")
        } catch {
            throw CLIError.invalidHAR("HAR file could not be read")
        }
    }

    private static func normalizationErrors(in archive: HARArchive) -> [String] {
        do {
            _ = try HARNormalizer.normalize(archive)
            return []
        } catch HARLoaderError.invalidBase64Body {
            return ["HAR response body declared as base64 could not be decoded"]
        } catch let error as HARNormalizerError {
            switch error {
            case .invalidURL(_, let entryIndex):
                return ["HAR entry \(entryIndex) has invalid URL"]
            case .sensitiveDataFound(let field, let entryIndex):
                return ["HAR entry \(entryIndex) contains sensitive data in \(field)"]
            }
        } catch {
            return ["HAR normalization failed"]
        }
    }

    private static func repeatedEndpoints(in methodsAndPaths: [String]) -> [(key: String, count: Int)] {
        let counts = methodsAndPaths.reduce(into: [String: Int]()) { partial, item in
            partial[item, default: 0] += 1
        }
        return counts
            .filter { $0.value > 1 }
            .map { (key: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                lhs.key < rhs.key
            }
    }

    private static func contentTypes(in archive: HARArchive) -> [String] {
        let responseHeaderTypes = archive.entries.compactMap { entry in
            entry.response.content.mimeType ?? entry.response.headers.first(where: { $0.name.caseInsensitiveCompare("Content-Type") == .orderedSame })?.value
        }
        return Array(Set(responseHeaderTypes)).sorted()
    }

    private static func isSensitiveWarning(_ warning: String) -> Bool {
        warning.localizedCaseInsensitiveContains("sensitive")
    }

    private static func isUnsupportedWarning(_ warning: String) -> Bool {
        warning.localizedCaseInsensitiveContains("unsupported")
    }

    private static func bulleted(_ items: [String]) -> [String] {
        items.map { "- \($0)" }
    }

    private static func humanizeWarning(_ warning: String) -> String {
        guard !warning.isEmpty else { return warning }

        if let range = warning.range(of: ": ") {
            let prefix = warning[..<range.upperBound]
            let suffix = warning[range.upperBound...]
            guard let first = suffix.first else { return warning }
            return String(prefix) + String(first).uppercased() + suffix.dropFirst()
        }

        guard let first = warning.first else { return warning }
        return String(first).uppercased() + warning.dropFirst()
    }

    private static func list(_ items: [String], empty: String) -> String {
        items.isEmpty ? empty : items.joined(separator: ", ")
    }

    private static func normalizedFileURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    private static func failure(_ error: CLIError) -> CLICommandResult {
        CLICommandResult(stdout: "", stderr: error.errorDescription ?? "Command failed", exitCode: error.exitCode.rawValue)
    }
}
