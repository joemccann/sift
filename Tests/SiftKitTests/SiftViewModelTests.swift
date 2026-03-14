import Foundation
import XCTest
@testable import DuckDBAdapter
@testable import SiftCore
@testable import SiftKit

@MainActor
final class SiftViewModelTests: XCTestCase {
    func testProviderDiagnosticsDetectsCliAndKeys() {
        let secretStore = MemorySecretStore(keys: [.openAI: "secret"])
        let statuses = ProviderDiagnostics.detect(
            environment: [
                "PATH": "/tooling:/bin",
            ],
            secretStore: secretStore,
            executableExists: { path in
                path == "/tooling/claude" || path == "/tooling/codex"
            }
        )

        XCTAssertEqual(statuses.first(where: { $0.provider == .claude })?.cliInstalled, true)
        XCTAssertEqual(statuses.first(where: { $0.provider == .openAI })?.apiKeyPresent, true)
        XCTAssertEqual(statuses.first(where: { $0.provider == .gemini })?.cliInstalled, false)
    }

    func testInitialStateRequiresSetupWhenNoSnapshotExists() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        XCTAssertTrue(viewModel.requiresInitialSetup)
        XCTAssertTrue(viewModel.isSetupFlowPresented)
    }

    func testCompleteSetupPersistsSettingsAndStoresAPIKey() {
        let sessionStore = MemorySessionStore()
        let secretStore = MemorySecretStore()
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: sessionStore,
            secretStore: secretStore,
            environment: ["PATH": "/bin"]
        )

        viewModel.completeSetup(
            defaultProvider: .gemini,
            authMode: .apiKey,
            model: "gemini-2.5-flash",
            apiKey: "gem-key"
        )

        XCTAssertFalse(viewModel.requiresInitialSetup)
        XCTAssertEqual(sessionStore.lastSaved?.settings.defaultProvider, .gemini)
        XCTAssertEqual(secretStore.keys[.gemini], "gem-key")
    }

    func testImportSourceSelectsParquet() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )
        let url = URL(fileURLWithPath: "/tmp/prices.parquet")

        viewModel.importSource(url: url)

        XCTAssertEqual(viewModel.selectedSource?.displayName, "prices.parquet")
        XCTAssertEqual(viewModel.sources.count, 1)
    }

    func testSendPromptWithoutSourceAppendsGuidance() async {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )
        viewModel.composerText = "show tables"

        await viewModel.sendPrompt()

        XCTAssertEqual(viewModel.transcript.last?.role, .assistant)
        XCTAssertTrue(viewModel.transcript.last?.body.contains("Open a local `.duckdb` or `.parquet` source first") == true)
    }

    func testSendPromptExecutesAndStoresLastResult() async {
        let result = DuckDBExecutionResult(
            binaryPath: "/opt/homebrew/bin/duckdb",
            arguments: [":memory:", "-table", "-c", "SELECT 1;"],
            sql: "SELECT 1;",
            stdout: "answer\n1\n",
            stderr: "",
            exitCode: 0,
            startedAt: Date(),
            endedAt: Date()
        )

        let viewModel = SiftViewModel(
            executor: MockExecutor(result: result),
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/prices.parquet"))

        await viewModel.triggerPrompt("Preview this parquet file")

        XCTAssertEqual(viewModel.lastExecution?.stdout, "answer\n1\n")
        XCTAssertTrue(viewModel.isDiagnosticsDrawerPresented)
        XCTAssertEqual(viewModel.transcript.last?.title, "Command Result")
    }

    func testProviderPromptUsesChatResponder() async {
        let response = ProviderChatResponse(provider: .claude, text: "Use rolling windows and watch regime shifts.")
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: response),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )
        viewModel.composerText = "Explain momentum factor construction"

        await viewModel.sendPrompt()

        XCTAssertEqual(viewModel.transcript.last?.title, "Claude")
        XCTAssertEqual(viewModel.transcript.last?.body, response.text)
    }

    func testProviderResponseWithSQLAutoExecutes() async {
        let responseText = """
        Here are the tables:

        ```sql
        SHOW TABLES;
        ```
        """
        let duckResult = DuckDBExecutionResult(
            binaryPath: "/opt/homebrew/bin/duckdb",
            arguments: [],
            sql: "SHOW TABLES;",
            stdout: "name\nmarket\nprices\n",
            stderr: "",
            exitCode: 0,
            startedAt: Date(),
            endedAt: Date()
        )

        let viewModel = SiftViewModel(
            executor: MockExecutor(result: duckResult),
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: responseText)),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/market.duckdb"))
        viewModel.composerText = "what symbols have the highest volume this week"

        await viewModel.sendPrompt()

        // Should have: user message + result only (no provider text, no SQL preview)
        let titles = viewModel.transcript.map(\.title)
        XCTAssertFalse(titles.contains("Claude"), "Provider response should be hidden when SQL auto-executes")
        XCTAssertFalse(titles.contains("Running Query"), "SQL preview should be hidden")
        XCTAssertTrue(titles.contains("Result"), "Should show query result directly")
        XCTAssertEqual(viewModel.lastExecution?.stdout, "name\nmarket\nprices\n")
    }

    func testProviderResponseWithoutSQLDoesNotAutoExecute() async {
        let response = ProviderChatResponse(provider: .claude, text: "No SQL here, just a plain answer.")
        let viewModel = SiftViewModel(
            executor: MockExecutor(result: DuckDBExecutionResult(binaryPath: "", arguments: [], sql: "", stdout: "", stderr: "", exitCode: 0, startedAt: Date(), endedAt: Date())),
            chatResponder: MockChatResponder(response: response),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/market.duckdb"))
        viewModel.composerText = "explain momentum"

        await viewModel.sendPrompt()

        let titles = viewModel.transcript.map(\.title)
        XCTAssertTrue(titles.contains("Claude"))
        XCTAssertFalse(titles.contains("Running Query"), "Should NOT auto-execute without SQL")
    }

    func testRawDuckDBPromptExecutesThroughExecutor() async {
        let result = DuckDBExecutionResult(
            binaryPath: "/opt/homebrew/bin/duckdb",
            arguments: ["--help"],
            sql: "",
            stdout: "usage",
            stderr: "",
            exitCode: 0,
            startedAt: Date(),
            endedAt: Date()
        )

        let viewModel = SiftViewModel(
            executor: MockExecutor(result: result),
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )
        viewModel.composerText = "/duckdb --help"

        await viewModel.sendPrompt()

        XCTAssertEqual(viewModel.lastExecution?.arguments, ["--help"])
        XCTAssertEqual(viewModel.transcript.last?.title, "DuckDB CLI Result")
    }

    func testSnapshotRestoresSelectedSourceAndTranscript() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/market.duckdb"), kind: .duckdb)
        let snapshot = AppSessionSnapshot(
            settings: AppSettings(hasCompletedSetup: true, defaultProvider: .openAI),
            sources: [source],
            selectedSourceID: source.id,
            transcript: [
                TranscriptItem(role: .assistant, title: "Saved", body: "Restored conversation")
            ]
        )

        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .openAI, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: snapshot),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        XCTAssertEqual(viewModel.selectedProvider, .openAI)
        XCTAssertEqual(viewModel.selectedSource, source)
        XCTAssertEqual(viewModel.transcript.last?.body, "Restored conversation")
        XCTAssertFalse(viewModel.isSetupFlowPresented)
    }

    func testScanDirectoryImportsDiscoveredSources() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sift-vm-scan-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let parquet = tempDir.appendingPathComponent("data.parquet")
        let duckdb = tempDir.appendingPathComponent("market.duckdb")
        FileManager.default.createFile(atPath: parquet.path, contents: nil)
        FileManager.default.createFile(atPath: duckdb.path, contents: nil)

        viewModel.scanDirectory(tempDir)

        XCTAssertEqual(viewModel.sources.count, 2)
        XCTAssertNotNil(viewModel.selectedSource)
        XCTAssertTrue(viewModel.transcript.contains(where: { $0.title == "Sources Discovered" }))
    }

    func testScanDirectorySkipsDuplicates() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sift-vm-scan-dup-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let parquet = tempDir.appendingPathComponent("data.parquet")
        FileManager.default.createFile(atPath: parquet.path, contents: nil)

        viewModel.importSource(url: parquet)
        let countBefore = viewModel.sources.count

        viewModel.scanDirectory(tempDir)

        XCTAssertEqual(viewModel.sources.count, countBefore)
    }

    func testMetalSnapshotTracksDestinationAndProviderReadiness() {
        let secretStore = MemorySecretStore(keys: [.gemini: "gem-key"])
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: secretStore,
            environment: [
                "PATH": "/tooling:/bin",
            ]
        )

        viewModel.selectedDestination = .settings

        XCTAssertEqual(viewModel.metalSnapshot.destination, .settings)
        XCTAssertEqual(viewModel.metalSnapshot.providerReadiness, 1)
        XCTAssertEqual(viewModel.metalSnapshot.executionState, .idle)
    }

    func testMetalSnapshotReflectsSelectedSourceAndExecutionOutcome() async {
        let result = DuckDBExecutionResult(
            binaryPath: "/opt/homebrew/bin/duckdb",
            arguments: [":memory:", "-table", "-c", "SELECT 1;"],
            sql: "SELECT 1;",
            stdout: "answer\n1\n",
            stderr: "",
            exitCode: 0,
            startedAt: Date(),
            endedAt: Date()
        )

        let viewModel = SiftViewModel(
            executor: MockExecutor(result: result),
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/prices.parquet"))

        await viewModel.triggerPrompt("Preview this parquet file")

        XCTAssertEqual(viewModel.metalSnapshot.sourceKind, .parquet)
        XCTAssertEqual(viewModel.metalSnapshot.executionState, .success)
        XCTAssertGreaterThanOrEqual(viewModel.metalSnapshot.transcriptCount, 1)
    }
}
