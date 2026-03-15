import Foundation
import SiftCore

public struct ProviderChatResponse: Equatable, Sendable {
    public let provider: ProviderKind
    public let text: String
}

public enum ProviderChatError: Error, LocalizedError, Equatable {
    case cliUnavailable(String)
    case missingAPIKey(String)
    case processFailure(String)
    case malformedOutput(String)

    public var errorDescription: String? {
        switch self {
        case let .cliUnavailable(message),
             let .missingAPIKey(message),
             let .processFailure(message),
             let .malformedOutput(message):
            return message
        }
    }
}

public struct ProviderSQLResponse: Equatable, Sendable {
    public let provider: ProviderKind
    public let sql: String
    public let explanation: String
}

public protocol ProviderResponding: Sendable {
    func respond(
        prompt: String,
        source: DataSource?,
        transcript: [TranscriptItem],
        settings: AppSettings,
        providerStatuses: [ProviderStatus]
    ) async throws -> ProviderChatResponse

    func generateSQL(
        prompt: String,
        source: DataSource,
        transcript: [TranscriptItem],
        settings: AppSettings,
        providerStatuses: [ProviderStatus]
    ) async throws -> ProviderSQLResponse
}

public struct ProcessExecutionResult: Equatable, Sendable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32
}

public protocol ProcessExecuting: Sendable {
    func execute(
        command: String,
        arguments: [String],
        environment: [String: String]
    ) async throws -> ProcessExecutionResult
}

public final class SystemProcessExecutor: ProcessExecuting, @unchecked Sendable {
    public init() {}

    public func execute(
        command: String,
        arguments: [String],
        environment: [String: String]
    ) async throws -> ProcessExecutionResult {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: command)
            process.arguments = arguments
            process.environment = environment

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            do {
                try process.run()
            } catch {
                throw ProviderChatError.processFailure("Failed to launch \(command): \(error.localizedDescription)")
            }

            process.waitUntilExit()
            let stdout = String(decoding: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let stderr = String(decoding: stderrPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)

            return ProcessExecutionResult(stdout: stdout, stderr: stderr, exitCode: process.terminationStatus)
        }.value
    }
}

public final class ProviderChatService: ProviderResponding, @unchecked Sendable {
    private let processExecutor: any ProcessExecuting
    private let secretStore: any ProviderSecretStoring
    private let baseEnvironment: [String: String]

    public init(
        processExecutor: any ProcessExecuting = SystemProcessExecutor(),
        secretStore: any ProviderSecretStoring = KeychainStore(),
        baseEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.processExecutor = processExecutor
        self.secretStore = secretStore
        self.baseEnvironment = baseEnvironment
    }

    public func respond(
        prompt: String,
        source: DataSource?,
        transcript: [TranscriptItem],
        settings: AppSettings,
        providerStatuses: [ProviderStatus]
    ) async throws -> ProviderChatResponse {
        let provider = settings.defaultProvider
        let preference = settings.preference(for: provider)

        guard let status = providerStatuses.first(where: { $0.provider == provider }), status.cliInstalled, let cliPath = status.cliPath else {
            throw ProviderChatError.cliUnavailable("`\(provider.cliCommand)` is not available on this Mac. Install the local CLI first. This build uses the provider CLI for both subscription and API-key-backed chat.")
        }

        let fallbackAPIKey = apiKey(for: provider, environment: baseEnvironment)
        var environment = preparedEnvironment(for: provider, authMode: preference.authMode)
        let wrappedPrompt = wrappedPrompt(prompt: prompt, source: source, transcript: transcript)
        let arguments: [String]
        var codexOutputPath: String?

        switch provider {
        case .claude:
            arguments = claudeArguments(prompt: wrappedPrompt, model: preference.customModel)
        case .openAI:
            let invocation = codexInvocation(prompt: wrappedPrompt, model: preference.customModel)
            arguments = invocation.arguments
            codexOutputPath = invocation.outputPath
        case .gemini:
            arguments = geminiArguments(prompt: wrappedPrompt, model: preference.customModel)
        }

        if preference.authMode == .apiKey {
            let key = apiKey(for: provider, environment: environment)
            guard !key.isEmpty else {
                throw ProviderChatError.missingAPIKey("No API key is configured for \(provider.displayName). Add one in Settings or complete setup with API key mode.")
            }
            environment[provider.preferredAPIKeyEnvironmentName] = key
        }

        var result = try await processExecutor.execute(
            command: cliPath,
            arguments: arguments,
            environment: environment
        )

        if result.exitCode != 0,
           preference.authMode == .localCLI,
           !fallbackAPIKey.isEmpty {
            var fallbackEnvironment = preparedEnvironment(for: provider, authMode: .apiKey)
            fallbackEnvironment[provider.preferredAPIKeyEnvironmentName] = fallbackAPIKey
            result = try await processExecutor.execute(
                command: cliPath,
                arguments: arguments,
                environment: fallbackEnvironment
            )
        }

        guard result.exitCode == 0 else {
            let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ProviderChatError.processFailure(message.isEmpty ? "\(provider.displayName) exited with status \(result.exitCode)." : message)
        }

        let text = try parseResponse(from: result.stdout, provider: provider, codexOutputPath: codexOutputPath)
        cleanupTemporaryOutput(at: codexOutputPath)

        return ProviderChatResponse(
            provider: provider,
            text: text
        )
    }

    public func generateSQL(
        prompt: String,
        source: DataSource,
        transcript: [TranscriptItem],
        settings: AppSettings,
        providerStatuses: [ProviderStatus]
    ) async throws -> ProviderSQLResponse {
        let provider = settings.defaultProvider
        let preference = settings.preference(for: provider)

        guard let status = providerStatuses.first(where: { $0.provider == provider }), status.cliInstalled, let cliPath = status.cliPath else {
            throw ProviderChatError.cliUnavailable("`\(provider.cliCommand)` is not available on this Mac. Install the local CLI first.")
        }

        let sqlPrompt = sqlGenerationPrompt(prompt: prompt, source: source, transcript: transcript)
        let fallbackAPIKey = apiKey(for: provider, environment: baseEnvironment)
        var environment = preparedEnvironment(for: provider, authMode: preference.authMode)
        let arguments: [String]
        var codexOutputPath: String?

        switch provider {
        case .claude:
            arguments = claudeArguments(prompt: sqlPrompt, model: preference.customModel)
        case .openAI:
            let invocation = codexInvocation(prompt: sqlPrompt, model: preference.customModel)
            arguments = invocation.arguments
            codexOutputPath = invocation.outputPath
        case .gemini:
            arguments = geminiArguments(prompt: sqlPrompt, model: preference.customModel)
        }

        if preference.authMode == .apiKey {
            let key = apiKey(for: provider, environment: environment)
            guard !key.isEmpty else {
                throw ProviderChatError.missingAPIKey("No API key is configured for \(provider.displayName).")
            }
            environment[provider.preferredAPIKeyEnvironmentName] = key
        }

        var result = try await processExecutor.execute(
            command: cliPath,
            arguments: arguments,
            environment: environment
        )

        if result.exitCode != 0,
           preference.authMode == .localCLI,
           !fallbackAPIKey.isEmpty {
            var fallbackEnvironment = preparedEnvironment(for: provider, authMode: .apiKey)
            fallbackEnvironment[provider.preferredAPIKeyEnvironmentName] = fallbackAPIKey
            result = try await processExecutor.execute(
                command: cliPath,
                arguments: arguments,
                environment: fallbackEnvironment
            )
        }

        guard result.exitCode == 0 else {
            let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ProviderChatError.processFailure(message.isEmpty ? "\(provider.displayName) exited with status \(result.exitCode)." : message)
        }

        let text = try parseResponse(from: result.stdout, provider: provider, codexOutputPath: codexOutputPath)
        cleanupTemporaryOutput(at: codexOutputPath)

        let (sql, explanation) = Self.extractSQL(from: text)
        return ProviderSQLResponse(provider: provider, sql: sql, explanation: explanation)
    }

    static func extractSQL(from text: String) -> (sql: String, explanation: String) {
        // Try to extract SQL from markdown code blocks first
        let fencedPattern = "```(?:sql)?\\s*\\n([\\s\\S]*?)\\n\\s*```"
        if let regex = try? NSRegularExpression(pattern: fencedPattern, options: []),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let sqlRange = Range(match.range(at: 1), in: text) {
            let sql = String(text[sqlRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            // Everything outside the code block is the explanation
            let explanation = text.replacingOccurrences(of: String(text[Range(match.range, in: text)!]), with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (sql, explanation.isEmpty ? "Generated SQL from your request." : explanation)
        }

        // Fallback: look for lines that start with SQL keywords
        let lines = text.components(separatedBy: .newlines)
        var sqlLines: [String] = []
        var explanationLines: [String] = []
        let sqlKeywords = ["select", "with", "insert", "update", "delete", "create", "drop", "alter",
                          "show", "describe", "pragma", "from", "summarize", "explain", "copy"]

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let firstWord = trimmed.split(separator: " ").first?.lowercased() ?? ""
            if sqlKeywords.contains(firstWord) || (!sqlLines.isEmpty && !trimmed.isEmpty && !trimmed.hasPrefix("*") && !trimmed.hasPrefix("-") && !trimmed.hasPrefix("#")) {
                sqlLines.append(line)
            } else {
                explanationLines.append(line)
            }
        }

        if !sqlLines.isEmpty {
            let sql = sqlLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            let explanation = explanationLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return (sql, explanation.isEmpty ? "Generated SQL from your request." : explanation)
        }

        // Last resort: treat the whole thing as an explanation (no SQL extracted)
        return ("", text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func sqlGenerationPrompt(
        prompt: String,
        source: DataSource,
        transcript: [TranscriptItem]
    ) -> String {
        let transcriptTail = transcript.suffix(4).map { item in
            "[\(item.role.rawValue)] \(item.title): \(item.body)"
        }.joined(separator: "\n")

        let sourceContext: String
        switch source.kind {
        case .parquet:
            sourceContext = """
            The source is a Parquet file. Use read_parquet('\(source.path)') to query it.
            Example: SELECT * FROM read_parquet('\(source.path)') LIMIT 10;
            """
        case .csv:
            sourceContext = """
            The source is a CSV file. Use read_csv('\(source.path)') to query it.
            Example: SELECT * FROM read_csv('\(source.path)') LIMIT 10;
            """
        case .json:
            sourceContext = """
            The source is a JSON file. Use read_json('\(source.path)') to query it.
            Example: SELECT * FROM read_json('\(source.path)') LIMIT 10;
            """
        case .duckdb:
            if let schema = source.schemaSummary {
                sourceContext = """
                The source is a DuckDB database at: \(source.path)
                
                Known schema:
                \(schema)
                
                Use fully qualified table names if the schema is not 'main' (e.g., SELECT * FROM md.equities_daily).
                """
            } else {
                sourceContext = """
                The source is a DuckDB database at: \(source.path)
                Query tables directly. To discover tables: SELECT table_schema, table_name FROM information_schema.tables;
                """
            }
        }

        return """
        You are a SQL generation assistant inside Sift, a native macOS DuckDB query tool.

        \(sourceContext)

        Recent conversation:
        \(transcriptTail)

        The user wants to query their data using natural language. Generate a valid DuckDB SQL query that answers their question. Return ONLY the SQL inside a ```sql code block, followed by a brief one-line explanation of what the query does.

        If the request is ambiguous or you need the schema first, generate a query that would help (like SHOW TABLES or DESCRIBE).

        User request:
        \(prompt)
        """
    }

    private func wrappedPrompt(
        prompt: String,
        source: DataSource?,
        transcript: [TranscriptItem]
    ) -> String {
        let transcriptTail = transcript.suffix(4).map { item in
            "[\(item.role.rawValue)] \(item.title): \(item.body)"
        }.joined(separator: "\n")

        if let source {
            return """
            You are the assistant inside Sift, a native macOS app for local parquet and DuckDB analysis.

            Current source:
            - name: \(source.displayName)
            - kind: \(source.kind.rawValue)
            - path: \(source.path)

            Recent transcript:
            \(transcriptTail)

            Respond concisely. If a DuckDB query would help, include it plainly and say what it does.

            User prompt:
            \(prompt)
            """
        }

        return """
        You are the assistant inside Sift, a native macOS app for local parquet and DuckDB analysis.

        Recent transcript:
        \(transcriptTail)

        Respond concisely. If the user needs to run SQL, say so clearly.

        User prompt:
        \(prompt)
        """
    }

    private func preparedEnvironment(for provider: ProviderKind, authMode: ProviderAuthMode) -> [String: String] {
        var environment = baseEnvironment

        if authMode == .localCLI {
            for key in provider.apiKeyEnvironmentNames {
                environment.removeValue(forKey: key)
            }
        }

        return environment
    }

    private func apiKey(for provider: ProviderKind, environment: [String: String]) -> String {
        if let stored = secretStore.apiKey(for: provider), !stored.isEmpty {
            return stored
        }

        for key in provider.apiKeyEnvironmentNames {
            if let value = environment[key], !value.isEmpty {
                return value
            }
        }

        return ""
    }

    private func claudeArguments(prompt: String, model: String) -> [String] {
        var arguments = [
            "-p",
            prompt,
            "--output-format",
            "json",
            "--no-session-persistence",
            "--tools",
            "",
        ]
        if !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            arguments.append(contentsOf: ["--model", model])
        }
        return arguments
    }

    private func geminiArguments(prompt: String, model: String) -> [String] {
        var arguments = [
            "--prompt",
            prompt,
            "--output-format",
            "json",
        ]
        if !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            arguments.append(contentsOf: ["--model", model])
        }
        return arguments
    }

    private func codexInvocation(prompt: String, model: String) -> (arguments: [String], outputPath: String) {
        let outputPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("txt")
            .path

        var arguments: [String] = []
        if !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            arguments.append(contentsOf: ["-m", model])
        }
        arguments.append(contentsOf: [
            "exec",
            prompt,
            "--output-last-message",
            outputPath,
            "--sandbox",
            "read-only",
            "--ephemeral",
            "--skip-git-repo-check",
            "--color",
            "never",
        ])
        return (arguments, outputPath)
    }

    private func parseResponse(from output: String, provider: ProviderKind, codexOutputPath: String?) throws -> String {
        switch provider {
        case .claude:
            let data = Data(output.utf8)
            let decoded = try JSONDecoder().decode(ClaudeResponse.self, from: data)
            return decoded.result.trimmingCharacters(in: .whitespacesAndNewlines)
        case .gemini:
            guard let start = output.firstIndex(of: "{") else {
                throw ProviderChatError.malformedOutput("Gemini did not return JSON output.")
            }
            let jsonString = String(output[start...])
            let data = Data(jsonString.utf8)
            let decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
            return decoded.response.trimmingCharacters(in: .whitespacesAndNewlines)
        case .openAI:
            guard let codexOutputPath else {
                throw ProviderChatError.malformedOutput("Codex did not provide an output file path.")
            }
            let fileOutput = (try? String(contentsOfFile: codexOutputPath, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if fileOutput.isEmpty {
                throw ProviderChatError.malformedOutput("Codex did not return a final message.")
            }
            return fileOutput
        }
    }

    private func cleanupTemporaryOutput(at path: String?) {
        guard let path else { return }
        try? FileManager.default.removeItem(atPath: path)
    }
}

private struct ClaudeResponse: Decodable {
    let result: String
}

private struct GeminiResponse: Decodable {
    let response: String
}
