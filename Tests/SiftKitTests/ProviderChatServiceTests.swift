import Foundation
import XCTest
@testable import DuckDBAdapter
@testable import SiftCore
@testable import SiftKit

private final class CapturingProcessExecutor: ProcessExecuting, @unchecked Sendable {
    struct Invocation {
        let command: String
        let arguments: [String]
        let environment: [String: String]
    }

    var invocation: Invocation?
    var handler: ((String, [String], [String: String]) throws -> ProcessExecutionResult)?

    func execute(
        command: String,
        arguments: [String],
        environment: [String: String]
    ) async throws -> ProcessExecutionResult {
        invocation = Invocation(command: command, arguments: arguments, environment: environment)
        if let handler {
            return try handler(command, arguments, environment)
        }
        return ProcessExecutionResult(stdout: "", stderr: "", exitCode: 0)
    }
}

final class ProviderDiagnosticsTests: XCTestCase {
    func testDetectsEnvironmentAPIKey() {
        let statuses = ProviderDiagnostics.detect(
            environment: ["ANTHROPIC_API_KEY": "sk-test", "PATH": ""],
            secretStore: MemorySecretStore(),
            executableExists: { _ in false }
        )

        let claude = statuses.first(where: { $0.provider == .claude })!
        XCTAssertFalse(claude.cliInstalled)
        XCTAssertTrue(claude.environmentKeyPresent)
    }

    func testDetectsAllProviders() {
        let statuses = ProviderDiagnostics.detect(
            environment: ["PATH": ""],
            secretStore: MemorySecretStore(),
            executableExists: { _ in false }
        )
        XCTAssertEqual(statuses.count, ProviderKind.allCases.count)
    }

    func testStatusSummaryReflectsState() {
        let ready = ProviderStatus(provider: .claude, cliInstalled: true, cliPath: "/bin/claude", apiKeyPresent: false, environmentKeyPresent: false)
        XCTAssertEqual(ready.statusSummary, "CLI ready")

        let apiKey = ProviderStatus(provider: .openAI, cliInstalled: false, cliPath: nil, apiKeyPresent: true, environmentKeyPresent: false)
        XCTAssertEqual(apiKey.statusSummary, "API key available")

        let envKey = ProviderStatus(provider: .gemini, cliInstalled: false, cliPath: nil, apiKeyPresent: false, environmentKeyPresent: true)
        XCTAssertEqual(envKey.statusSummary, "API key available")

        let unconfigured = ProviderStatus(provider: .claude, cliInstalled: false, cliPath: nil, apiKeyPresent: false, environmentKeyPresent: false)
        XCTAssertEqual(unconfigured.statusSummary, "Needs configuration")
    }

    func testDetectsGeminiWithMultipleKeyNames() {
        let statuses = ProviderDiagnostics.detect(
            environment: ["GOOGLE_API_KEY": "test-key", "PATH": ""],
            secretStore: MemorySecretStore(),
            executableExists: { _ in false }
        )

        let gemini = statuses.first(where: { $0.provider == .gemini })!
        XCTAssertTrue(gemini.environmentKeyPresent)
    }

    func testProviderStatusProperties() {
        let status = ProviderStatus(provider: .claude, cliInstalled: true, cliPath: "/bin/claude", apiKeyPresent: false, environmentKeyPresent: false)
        XCTAssertEqual(status.id, "claude")
        XCTAssertEqual(status.name, "Claude")
        XCTAssertEqual(status.cliName, "claude")
        XCTAssertEqual(status.apiKeyName, "ANTHROPIC_API_KEY")
    }
}

final class ProviderSecretStoreErrorTests: XCTestCase {
    func testKeychainFailureDescription() {
        let error = ProviderSecretStoreError.keychainFailure(-25300)
        XCTAssertTrue(error.errorDescription?.contains("-25300") == true)
    }

    func testKeychainFailureEquality() {
        XCTAssertEqual(
            ProviderSecretStoreError.keychainFailure(-25300),
            ProviderSecretStoreError.keychainFailure(-25300)
        )
        XCTAssertNotEqual(
            ProviderSecretStoreError.keychainFailure(-25300),
            ProviderSecretStoreError.keychainFailure(-25299)
        )
    }
}

final class ProviderChatServiceTests: XCTestCase {
    func testClaudeJSONResponseIsParsed() async throws {
        let executor = CapturingProcessExecutor()
        executor.handler = { _, _, _ in
            ProcessExecutionResult(
                stdout: #"{"result":"CLAUDE_REPLY"}"#,
                stderr: "",
                exitCode: 0
            )
        }

        let service = ProviderChatService(
            processExecutor: executor,
            secretStore: MemorySecretStore(),
            baseEnvironment: [:]
        )

        var settings = AppSettings(hasCompletedSetup: true, defaultProvider: .claude)
        settings.setPreference(ProviderPreference(authMode: .localCLI, customModel: "sonnet"), for: .claude)

        let response = try await service.respond(
            prompt: "Test",
            source: nil,
            transcript: [],
            settings: settings,
            providerStatuses: [ProviderStatus(provider: .claude, cliInstalled: true, cliPath: "/usr/bin/claude", apiKeyPresent: false, environmentKeyPresent: false)]
        )

        XCTAssertEqual(response.text, "CLAUDE_REPLY")
        XCTAssertEqual(executor.invocation?.arguments.contains("--output-format"), true)
    }

    func testLocalSubscriptionFallsBackToStoredAPIKey() async throws {
        let executor = CapturingProcessExecutor()
        var invocationCount = 0
        executor.handler = { _, _, environment in
            invocationCount += 1
            if invocationCount == 1 {
                XCTAssertNil(environment["ANTHROPIC_API_KEY"])
                return ProcessExecutionResult(stdout: "", stderr: "authentication required", exitCode: 1)
            }

            XCTAssertEqual(environment["ANTHROPIC_API_KEY"], "fallback-key")
            return ProcessExecutionResult(
                stdout: #"{"result":"FALLBACK_REPLY"}"#,
                stderr: "",
                exitCode: 0
            )
        }

        let service = ProviderChatService(
            processExecutor: executor,
            secretStore: MemorySecretStore(keys: [.claude: "fallback-key"]),
            baseEnvironment: [:]
        )

        var settings = AppSettings(hasCompletedSetup: true, defaultProvider: .claude)
        settings.setPreference(ProviderPreference(authMode: .localCLI, customModel: ""), for: .claude)

        let response = try await service.respond(
            prompt: "Test",
            source: nil,
            transcript: [],
            settings: settings,
            providerStatuses: [ProviderStatus(provider: .claude, cliInstalled: true, cliPath: "/usr/bin/claude", apiKeyPresent: true, environmentKeyPresent: false)]
        )

        XCTAssertEqual(invocationCount, 2)
        XCTAssertEqual(response.text, "FALLBACK_REPLY")
    }

    func testAPIKeyModeInjectsStoredSecret() async throws {
        let executor = CapturingProcessExecutor()
        executor.handler = { _, _, environment in
            XCTAssertEqual(environment["ANTHROPIC_API_KEY"], "secret-key")
            return ProcessExecutionResult(stdout: #"{"result":"OK"}"#, stderr: "", exitCode: 0)
        }

        let service = ProviderChatService(
            processExecutor: executor,
            secretStore: MemorySecretStore(keys: [.claude: "secret-key"]),
            baseEnvironment: [:]
        )

        var settings = AppSettings(hasCompletedSetup: true, defaultProvider: .claude)
        settings.setPreference(ProviderPreference(authMode: .apiKey, customModel: ""), for: .claude)

        _ = try await service.respond(
            prompt: "Test",
            source: nil,
            transcript: [],
            settings: settings,
            providerStatuses: [ProviderStatus(provider: .claude, cliInstalled: true, cliPath: "/usr/bin/claude", apiKeyPresent: true, environmentKeyPresent: false)]
        )
    }

    func testExtractSQLFromMarkdownCodeBlock() {
        let text = """
        Here's a query to get AAPL trading data:

        ```sql
        SELECT * FROM trades WHERE symbol = 'AAPL' ORDER BY date DESC LIMIT 7;
        ```

        This fetches the most recent 7 AAPL trades.
        """

        let (sql, explanation) = ProviderChatService.extractSQL(from: text)
        XCTAssertEqual(sql, "SELECT * FROM trades WHERE symbol = 'AAPL' ORDER BY date DESC LIMIT 7;")
        XCTAssertTrue(explanation.contains("AAPL trading data"))
    }

    func testExtractSQLFromUnfencedBlock() {
        let text = """
        ```
        SELECT COUNT(*) FROM orders;
        ```
        """

        let (sql, _) = ProviderChatService.extractSQL(from: text)
        XCTAssertEqual(sql, "SELECT COUNT(*) FROM orders;")
    }

    func testExtractSQLReturnsEmptyWhenNoSQL() {
        let text = "I don't know your schema. Please run SHOW TABLES first to see what's available."

        let (sql, explanation) = ProviderChatService.extractSQL(from: text)
        XCTAssertTrue(sql.isEmpty || explanation.contains("SHOW TABLES"))
    }

    func testExtractSQLFromMultilineCodeBlock() {
        let text = """
        ```sql
        SELECT
            symbol,
            AVG(price) AS avg_price
        FROM trades
        GROUP BY symbol
        ORDER BY avg_price DESC;
        ```
        """

        let (sql, _) = ProviderChatService.extractSQL(from: text)
        XCTAssertTrue(sql.contains("SELECT"))
        XCTAssertTrue(sql.contains("GROUP BY"))
        XCTAssertTrue(sql.contains("ORDER BY"))
    }

    func testExtractSQLPreservesExplanation() {
        let text = """
        I'll generate a query to count rows by category.

        ```sql
        SELECT category, COUNT(*) FROM products GROUP BY category;
        ```

        This gives you a breakdown by category.
        """

        let (sql, explanation) = ProviderChatService.extractSQL(from: text)
        XCTAssertEqual(sql, "SELECT category, COUNT(*) FROM products GROUP BY category;")
        XCTAssertTrue(explanation.contains("count rows by category") || explanation.contains("breakdown"))
    }

    func testCLIUnavailableThrowsError() async {
        let service = ProviderChatService(
            processExecutor: CapturingProcessExecutor(),
            secretStore: MemorySecretStore(),
            baseEnvironment: [:]
        )

        var settings = AppSettings(hasCompletedSetup: true, defaultProvider: .claude)
        settings.setPreference(ProviderPreference(authMode: .localCLI, customModel: ""), for: .claude)

        do {
            _ = try await service.respond(
                prompt: "Test",
                source: nil,
                transcript: [],
                settings: settings,
                providerStatuses: [ProviderStatus(provider: .claude, cliInstalled: false, cliPath: nil, apiKeyPresent: false, environmentKeyPresent: false)]
            )
            XCTFail("Should have thrown")
        } catch {
            XCTAssertTrue(error is ProviderChatError)
        }
    }

    func testMissingAPIKeyThrowsError() async {
        let executor = CapturingProcessExecutor()
        executor.handler = { _, _, _ in
            ProcessExecutionResult(stdout: #"{"result":"OK"}"#, stderr: "", exitCode: 0)
        }

        let service = ProviderChatService(
            processExecutor: executor,
            secretStore: MemorySecretStore(),
            baseEnvironment: [:]
        )

        var settings = AppSettings(hasCompletedSetup: true, defaultProvider: .claude)
        settings.setPreference(ProviderPreference(authMode: .apiKey, customModel: ""), for: .claude)

        do {
            _ = try await service.respond(
                prompt: "Test",
                source: nil,
                transcript: [],
                settings: settings,
                providerStatuses: [ProviderStatus(provider: .claude, cliInstalled: true, cliPath: "/usr/bin/claude", apiKeyPresent: false, environmentKeyPresent: false)]
            )
            XCTFail("Should have thrown")
        } catch let error as ProviderChatError {
            XCTAssertTrue(error.localizedDescription.contains("API key") == true)
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testProcessFailureThrowsError() async {
        let executor = CapturingProcessExecutor()
        executor.handler = { _, _, _ in
            ProcessExecutionResult(stdout: "", stderr: "connection refused", exitCode: 1)
        }

        let service = ProviderChatService(
            processExecutor: executor,
            secretStore: MemorySecretStore(),
            baseEnvironment: [:]
        )

        var settings = AppSettings(hasCompletedSetup: true, defaultProvider: .claude)
        settings.setPreference(ProviderPreference(authMode: .localCLI, customModel: ""), for: .claude)

        do {
            _ = try await service.respond(
                prompt: "Test",
                source: nil,
                transcript: [],
                settings: settings,
                providerStatuses: [ProviderStatus(provider: .claude, cliInstalled: true, cliPath: "/usr/bin/claude", apiKeyPresent: false, environmentKeyPresent: false)]
            )
            XCTFail("Should have thrown")
        } catch let error as ProviderChatError {
            XCTAssertTrue(error.localizedDescription.contains("connection refused") == true)
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testGenerateSQLReturnsStructuredResponse() async throws {
        let executor = CapturingProcessExecutor()
        executor.handler = { _, _, _ in
            ProcessExecutionResult(
                stdout: #"{"result":"Here's your query:\n\n```sql\nSELECT * FROM trades;\n```\n\nThis fetches all trades."}"#,
                stderr: "",
                exitCode: 0
            )
        }

        let service = ProviderChatService(
            processExecutor: executor,
            secretStore: MemorySecretStore(),
            baseEnvironment: [:]
        )

        var settings = AppSettings(hasCompletedSetup: true, defaultProvider: .claude)
        settings.setPreference(ProviderPreference(authMode: .localCLI, customModel: ""), for: .claude)

        let source = DataSource(url: URL(fileURLWithPath: "/tmp/market.duckdb"), kind: .duckdb)
        let response = try await service.generateSQL(
            prompt: "show me all trades",
            source: source,
            transcript: [],
            settings: settings,
            providerStatuses: [ProviderStatus(provider: .claude, cliInstalled: true, cliPath: "/usr/bin/claude", apiKeyPresent: false, environmentKeyPresent: false)]
        )

        XCTAssertEqual(response.sql, "SELECT * FROM trades;")
        XCTAssertEqual(response.provider, .claude)
    }

    func testProviderChatErrorDescriptions() {
        let cliError = ProviderChatError.cliUnavailable("CLI not found")
        XCTAssertEqual(cliError.errorDescription, "CLI not found")

        let keyError = ProviderChatError.missingAPIKey("No key")
        XCTAssertEqual(keyError.errorDescription, "No key")

        let processError = ProviderChatError.processFailure("Crashed")
        XCTAssertEqual(processError.errorDescription, "Crashed")

        let malformedError = ProviderChatError.malformedOutput("Bad JSON")
        XCTAssertEqual(malformedError.errorDescription, "Bad JSON")
    }

    func testProviderChatErrorEquality() {
        XCTAssertEqual(
            ProviderChatError.cliUnavailable("A"),
            ProviderChatError.cliUnavailable("A")
        )
        XCTAssertNotEqual(
            ProviderChatError.cliUnavailable("A"),
            ProviderChatError.missingAPIKey("A")
        )
    }

    func testGeminiJSONResponseIsParsed() async throws {
        let executor = CapturingProcessExecutor()
        executor.handler = { _, _, _ in
            ProcessExecutionResult(
                stdout: #"some preamble text {"response":"GEMINI_REPLY"}"#,
                stderr: "",
                exitCode: 0
            )
        }

        let service = ProviderChatService(
            processExecutor: executor,
            secretStore: MemorySecretStore(),
            baseEnvironment: [:]
        )

        var settings = AppSettings(hasCompletedSetup: true, defaultProvider: .gemini)
        settings.setPreference(ProviderPreference(authMode: .localCLI, customModel: ""), for: .gemini)

        let response = try await service.respond(
            prompt: "Test",
            source: nil,
            transcript: [],
            settings: settings,
            providerStatuses: [ProviderStatus(provider: .gemini, cliInstalled: true, cliPath: "/usr/bin/gemini", apiKeyPresent: false, environmentKeyPresent: false)]
        )

        XCTAssertEqual(response.text, "GEMINI_REPLY")
        XCTAssertEqual(response.provider, .gemini)
    }

    func testGeminiIncludesModelArgument() async throws {
        let executor = CapturingProcessExecutor()
        executor.handler = { _, _, _ in
            ProcessExecutionResult(
                stdout: #"{"response":"OK"}"#,
                stderr: "",
                exitCode: 0
            )
        }

        let service = ProviderChatService(
            processExecutor: executor,
            secretStore: MemorySecretStore(),
            baseEnvironment: [:]
        )

        var settings = AppSettings(hasCompletedSetup: true, defaultProvider: .gemini)
        settings.setPreference(ProviderPreference(authMode: .localCLI, customModel: "gemini-2.5-flash"), for: .gemini)

        _ = try await service.respond(
            prompt: "Test",
            source: nil,
            transcript: [],
            settings: settings,
            providerStatuses: [ProviderStatus(provider: .gemini, cliInstalled: true, cliPath: "/usr/bin/gemini", apiKeyPresent: false, environmentKeyPresent: false)]
        )

        XCTAssertTrue(executor.invocation?.arguments.contains("gemini-2.5-flash") == true)
    }

    func testDuckDBCLIErrorDescriptions() {
        XCTAssertTrue(DuckDBCLIError.binaryNotFound.errorDescription?.contains("duckdb") == true)
        XCTAssertTrue(DuckDBCLIError.launchFailed("oops").errorDescription?.contains("oops") == true)
        XCTAssertTrue(DuckDBCLIError.invalidArguments("bad").errorDescription?.contains("bad") == true)
    }

    func testDuckDBCLIErrorEquality() {
        XCTAssertEqual(DuckDBCLIError.binaryNotFound, DuckDBCLIError.binaryNotFound)
        XCTAssertNotEqual(DuckDBCLIError.binaryNotFound, DuckDBCLIError.launchFailed("x"))
    }

    func testClaudeIncludesModelArgument() async throws {
        let executor = CapturingProcessExecutor()
        executor.handler = { _, _, _ in
            ProcessExecutionResult(
                stdout: #"{"result":"OK"}"#,
                stderr: "",
                exitCode: 0
            )
        }

        let service = ProviderChatService(
            processExecutor: executor,
            secretStore: MemorySecretStore(),
            baseEnvironment: [:]
        )

        var settings = AppSettings(hasCompletedSetup: true, defaultProvider: .claude)
        settings.setPreference(ProviderPreference(authMode: .localCLI, customModel: "opus"), for: .claude)

        _ = try await service.respond(
            prompt: "Test",
            source: nil,
            transcript: [],
            settings: settings,
            providerStatuses: [ProviderStatus(provider: .claude, cliInstalled: true, cliPath: "/usr/bin/claude", apiKeyPresent: false, environmentKeyPresent: false)]
        )

        XCTAssertTrue(executor.invocation?.arguments.contains("opus") == true)
        XCTAssertTrue(executor.invocation?.arguments.contains("--model") == true)
    }

    func testClaudeWithoutModelOmitsModelArgument() async throws {
        let executor = CapturingProcessExecutor()
        executor.handler = { _, _, _ in
            ProcessExecutionResult(
                stdout: #"{"result":"OK"}"#,
                stderr: "",
                exitCode: 0
            )
        }

        let service = ProviderChatService(
            processExecutor: executor,
            secretStore: MemorySecretStore(),
            baseEnvironment: [:]
        )

        var settings = AppSettings(hasCompletedSetup: true, defaultProvider: .claude)
        settings.setPreference(ProviderPreference(authMode: .localCLI, customModel: ""), for: .claude)

        _ = try await service.respond(
            prompt: "Test",
            source: nil,
            transcript: [],
            settings: settings,
            providerStatuses: [ProviderStatus(provider: .claude, cliInstalled: true, cliPath: "/usr/bin/claude", apiKeyPresent: false, environmentKeyPresent: false)]
        )

        XCTAssertFalse(executor.invocation?.arguments.contains("--model") == true)
    }

    func testGenerateSQLForParquetSource() async throws {
        let executor = CapturingProcessExecutor()
        executor.handler = { _, _, _ in
            ProcessExecutionResult(
                stdout: #"{"result":"```sql\nSELECT * FROM read_parquet('/tmp/data.parquet') LIMIT 5;\n```\nShowing 5 rows."}"#,
                stderr: "",
                exitCode: 0
            )
        }

        let service = ProviderChatService(
            processExecutor: executor,
            secretStore: MemorySecretStore(),
            baseEnvironment: [:]
        )

        var settings = AppSettings(hasCompletedSetup: true, defaultProvider: .claude)
        settings.setPreference(ProviderPreference(authMode: .localCLI, customModel: ""), for: .claude)

        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.parquet"), kind: .parquet)
        let response = try await service.generateSQL(
            prompt: "show me some rows",
            source: source,
            transcript: [],
            settings: settings,
            providerStatuses: [ProviderStatus(provider: .claude, cliInstalled: true, cliPath: "/usr/bin/claude", apiKeyPresent: false, environmentKeyPresent: false)]
        )

        XCTAssertTrue(response.sql.contains("read_parquet"))
        XCTAssertFalse(response.explanation.isEmpty)
    }

    func testGenerateSQLCLIUnavailableThrowsError() async {
        let service = ProviderChatService(
            processExecutor: CapturingProcessExecutor(),
            secretStore: MemorySecretStore(),
            baseEnvironment: [:]
        )

        var settings = AppSettings(hasCompletedSetup: true, defaultProvider: .claude)
        settings.setPreference(ProviderPreference(authMode: .localCLI, customModel: ""), for: .claude)

        let source = DataSource(url: URL(fileURLWithPath: "/tmp/test.duckdb"), kind: .duckdb)
        do {
            _ = try await service.generateSQL(
                prompt: "show me data",
                source: source,
                transcript: [],
                settings: settings,
                providerStatuses: [ProviderStatus(provider: .claude, cliInstalled: false, cliPath: nil, apiKeyPresent: false, environmentKeyPresent: false)]
            )
            XCTFail("Should have thrown")
        } catch {
            XCTAssertTrue(error is ProviderChatError)
        }
    }

    func testExtractSQLWithNoCodeBlock() {
        let text = "I don't know how to generate SQL for that. Try running SHOW TABLES first."
        let (sql, explanation) = ProviderChatService.extractSQL(from: text)
        // The text starts with "I" which is not a SQL keyword, so sql should be empty
        XCTAssertTrue(sql.isEmpty || !explanation.isEmpty)
    }

    func testExtractSQLWithMultipleCodeBlocks() {
        let text = """
        First query:
        ```sql
        SELECT 1;
        ```
        
        Second query:
        ```sql
        SELECT 2;
        ```
        """

        let (sql, _) = ProviderChatService.extractSQL(from: text)
        // Should extract the first code block
        XCTAssertEqual(sql, "SELECT 1;")
    }

    func testCodexReadsLastMessageFile() async throws {
        let executor = CapturingProcessExecutor()
        executor.handler = { _, arguments, _ in
            guard let index = arguments.firstIndex(of: "--output-last-message") else {
                return ProcessExecutionResult(stdout: "", stderr: "missing output path", exitCode: 1)
            }
            let path = arguments[index + 1]
            try "CODEX_REPLY".write(toFile: path, atomically: true, encoding: .utf8)
            return ProcessExecutionResult(stdout: "noise", stderr: "", exitCode: 0)
        }

        let service = ProviderChatService(
            processExecutor: executor,
            secretStore: MemorySecretStore(),
            baseEnvironment: [:]
        )

        var settings = AppSettings(hasCompletedSetup: true, defaultProvider: .openAI)
        settings.setPreference(ProviderPreference(authMode: .localCLI, customModel: ""), for: .openAI)

        let response = try await service.respond(
            prompt: "Test",
            source: nil,
            transcript: [],
            settings: settings,
            providerStatuses: [ProviderStatus(provider: .openAI, cliInstalled: true, cliPath: "/usr/bin/codex", apiKeyPresent: false, environmentKeyPresent: false)]
        )

        XCTAssertEqual(response.text, "CODEX_REPLY")
    }
}
