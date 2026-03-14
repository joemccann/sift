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

    func testRemoveSourceRemovesFromListAndDeselectsIfActive() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/a.parquet"))
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/b.duckdb"))
        XCTAssertEqual(viewModel.sources.count, 2)

        let sourceToRemove = viewModel.sources.first(where: { $0.displayName == "b.duckdb" })!
        viewModel.selectSource(sourceToRemove)
        XCTAssertEqual(viewModel.selectedSource, sourceToRemove)

        viewModel.removeSource(sourceToRemove)

        XCTAssertEqual(viewModel.sources.count, 1)
        XCTAssertEqual(viewModel.sources.first?.displayName, "a.parquet")
        // When removing the selected source, it falls back to the first remaining source
        XCTAssertEqual(viewModel.selectedSource?.displayName, "a.parquet")
        XCTAssertEqual(viewModel.transcript.last?.title, "Source Removed")
    }

    func testRemoveSourceKeepsSelectionWhenDifferentSourceRemoved() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/a.parquet"))
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/b.duckdb"))
        let firstSource = viewModel.sources.first(where: { $0.displayName == "a.parquet" })!
        viewModel.selectSource(firstSource)

        let otherSource = viewModel.sources.first(where: { $0.displayName == "b.duckdb" })!
        viewModel.removeSource(otherSource)

        XCTAssertEqual(viewModel.sources.count, 1)
        XCTAssertEqual(viewModel.selectedSource, firstSource)
    }

    func testRemoveAllSourcesClearsEverything() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/a.parquet"))
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/b.duckdb"))

        viewModel.removeAllSources()

        XCTAssertTrue(viewModel.sources.isEmpty)
        XCTAssertNil(viewModel.selectedSource)
        XCTAssertEqual(viewModel.transcript.last?.title, "Sources Cleared")
    }

    func testThinkingIndicatorAppearsAndIsReplacedForAssistantReply() async {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )
        viewModel.composerText = "What can you do?"

        await viewModel.sendPrompt()

        // The thinking item should have been replaced, not left in the transcript
        let thinkingItems = viewModel.transcript.filter { $0.kind == .thinking }
        XCTAssertTrue(thinkingItems.isEmpty, "Thinking items should be replaced after response")

        // The response should be present
        let assistantReplies = viewModel.transcript.filter { $0.role == .assistant && $0.kind == .text }
        XCTAssertFalse(assistantReplies.isEmpty, "Assistant reply should be present")
    }

    func testThinkingIndicatorAppearsAndIsReplacedForProviderPrompt() async {
        let response = ProviderChatResponse(provider: .claude, text: "Here is the analysis.")
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: response),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )
        viewModel.composerText = "Explain factor momentum"

        await viewModel.sendPrompt()

        let thinkingItems = viewModel.transcript.filter { $0.kind == .thinking }
        XCTAssertTrue(thinkingItems.isEmpty, "Thinking items should be replaced after provider response")
        XCTAssertEqual(viewModel.transcript.last?.body, "Here is the analysis.")
    }

    func testNaturalLanguageQueryGeneratesSQLAndExecutes() async {
        let duckResult = DuckDBExecutionResult(
            binaryPath: "/opt/homebrew/bin/duckdb",
            arguments: [":memory:", "-table", "-c", "SELECT * FROM trades WHERE symbol = 'AAPL';"],
            sql: "SELECT * FROM trades WHERE symbol = 'AAPL';",
            stdout: "symbol | price\nAAPL   | 185.50\n",
            stderr: "",
            exitCode: 0,
            startedAt: Date(),
            endedAt: Date()
        )

        let sqlResponse = ProviderSQLResponse(
            provider: .claude,
            sql: "SELECT * FROM trades WHERE symbol = 'AAPL';",
            explanation: "Fetching AAPL trades from the trades table."
        )

        let viewModel = SiftViewModel(
            executor: MockExecutor(result: duckResult),
            chatResponder: MockChatResponder(
                response: .init(provider: .claude, text: "ignored"),
                sqlResponse: sqlResponse
            ),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/market.duckdb"))

        await viewModel.triggerPrompt("give me the trading data for AAPL")

        // Should have: user message, source attached, SQL preview, command result
        let thinkingItems = viewModel.transcript.filter { $0.kind == .thinking }
        XCTAssertTrue(thinkingItems.isEmpty, "No thinking items should remain")

        // Find the SQL preview
        let sqlPreviews = viewModel.transcript.filter {
            if case .commandPreview = $0.kind { return true }
            return false
        }
        XCTAssertFalse(sqlPreviews.isEmpty, "Should contain a SQL preview")

        // Find the result
        let results = viewModel.transcript.filter {
            if case .commandResult = $0.kind { return true }
            return false
        }
        XCTAssertFalse(results.isEmpty, "Should contain query result")
        XCTAssertEqual(viewModel.lastExecution?.stdout, "symbol | price\nAAPL   | 185.50\n")
    }

    func testNaturalLanguageQueryWithEmptySQLFallsBackToExplanation() async {
        let sqlResponse = ProviderSQLResponse(
            provider: .claude,
            sql: "",
            explanation: "I'd need to know your table schema to generate a query. Try running SHOW TABLES first."
        )

        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(
                response: .init(provider: .claude, text: "ignored"),
                sqlResponse: sqlResponse
            ),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/market.duckdb"))

        await viewModel.triggerPrompt("what are the best performing stocks?")

        let thinkingItems = viewModel.transcript.filter { $0.kind == .thinking }
        XCTAssertTrue(thinkingItems.isEmpty)

        // Should fall back to showing the explanation text
        XCTAssertTrue(viewModel.transcript.contains(where: { $0.body.contains("I'd need to know your table schema") }))
    }

    func testClearCommandClearsTranscript() async {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [
                TranscriptItem(role: .assistant, title: "A", body: "Hello"),
                TranscriptItem(role: .user, title: "You", body: "Hi"),
            ])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )
        XCTAssertTrue(viewModel.transcript.count >= 2)

        viewModel.composerText = "/clear"
        await viewModel.sendPrompt()

        // After /clear, transcript is reset to initial welcome message
        XCTAssertEqual(viewModel.transcript.count, 1)
        XCTAssertTrue(viewModel.transcript.first?.body.contains("Welcome") == true)
    }

    func testSourcesCommandListsAttachedSources() async {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/a.parquet"))
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/b.duckdb"))

        viewModel.composerText = "/sources"
        await viewModel.sendPrompt()

        let lastItem = viewModel.transcript.last
        XCTAssertEqual(lastItem?.title, "Sources")
        XCTAssertTrue(lastItem?.body.contains("a.parquet") == true)
        XCTAssertTrue(lastItem?.body.contains("b.duckdb") == true)
    }

    func testSourcesCommandWithNoSourcesShowsGuidance() async {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.composerText = "/sources"
        await viewModel.sendPrompt()

        let lastItem = viewModel.transcript.last
        XCTAssertEqual(lastItem?.title, "Sources")
        XCTAssertTrue(lastItem?.body.contains("No sources attached") == true)
    }

    func testCopyCommandWithNoResultShowsGuidance() async {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.composerText = "/copy"
        await viewModel.sendPrompt()

        let lastItem = viewModel.transcript.last
        XCTAssertEqual(lastItem?.title, "Nothing to Copy")
    }

    func testCopyCommandAfterExecutionCopiesToClipboard() async {
        let result = DuckDBExecutionResult(
            binaryPath: "/opt/homebrew/bin/duckdb",
            arguments: [":memory:", "-table", "-c", "SELECT 42;"],
            sql: "SELECT 42;",
            stdout: "42\n",
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

        viewModel.composerText = "/copy"
        await viewModel.sendPrompt()

        let lastItem = viewModel.transcript.last
        XCTAssertEqual(lastItem?.title, "Copied")
        XCTAssertTrue(lastItem?.body.contains("clipboard") == true)
    }

    func testRerunWithNoCommandsShowsGuidance() async {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.composerText = "/rerun"
        await viewModel.sendPrompt()

        let lastItem = viewModel.transcript.last
        XCTAssertEqual(lastItem?.title, "No Commands")
    }

    func testRerunReExecutesLastCommand() async {
        let result = DuckDBExecutionResult(
            binaryPath: "/opt/homebrew/bin/duckdb",
            arguments: [":memory:", "-table", "-c", "SELECT 42;"],
            sql: "SELECT 42;",
            stdout: "42\n",
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

        viewModel.composerText = "/rerun"
        await viewModel.sendPrompt()

        let rerunResults = viewModel.transcript.filter { $0.title == "Re-run Result" }
        XCTAssertFalse(rerunResults.isEmpty)
    }

    func testImportSourceSelectsJSON() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )
        let url = URL(fileURLWithPath: "/tmp/data.json")

        viewModel.importSource(url: url)

        XCTAssertEqual(viewModel.selectedSource?.displayName, "data.json")
        XCTAssertEqual(viewModel.selectedSource?.kind, .json)
        XCTAssertEqual(viewModel.sources.count, 1)
    }

    func testImportUnsupportedFileShowsError() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )
        let url = URL(fileURLWithPath: "/tmp/data.xlsx")

        viewModel.importSource(url: url)

        XCTAssertTrue(viewModel.sources.isEmpty)
        XCTAssertEqual(viewModel.transcript.last?.title, "Unsupported Source")
    }

    func testSearchTranscriptFindsMatchingItems() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [
                TranscriptItem(role: .assistant, title: "A", body: "Hello world"),
                TranscriptItem(role: .user, title: "You", body: "Search for AAPL trades"),
                TranscriptItem(role: .assistant, title: "A", body: "Here are the AAPL results"),
            ])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.searchTranscript(query: "AAPL")

        XCTAssertEqual(viewModel.searchResults.count, 2)
        XCTAssertEqual(viewModel.searchQuery, "AAPL")
    }

    func testSearchTranscriptEmptyQueryClearsResults() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [
                TranscriptItem(role: .assistant, title: "A", body: "Hello world"),
            ])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.searchTranscript(query: "Hello")
        XCTAssertEqual(viewModel.searchResults.count, 1)

        viewModel.searchTranscript(query: "")
        XCTAssertTrue(viewModel.searchResults.isEmpty)
        XCTAssertEqual(viewModel.searchQuery, "")
    }

    func testSearchTranscriptIsCaseInsensitive() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [
                TranscriptItem(role: .assistant, title: "A", body: "DuckDB is great"),
            ])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.searchTranscript(query: "duckdb")
        XCTAssertEqual(viewModel.searchResults.count, 1)
    }

    func testSearchTranscriptMatchesTitle() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [
                TranscriptItem(role: .assistant, title: "Command Result", body: "exit 0"),
            ])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.searchTranscript(query: "Command")
        XCTAssertEqual(viewModel.searchResults.count, 1)
    }

    func testHistoryWithNoCommandsShowsGuidance() async {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.composerText = "/history"
        await viewModel.sendPrompt()

        let lastItem = viewModel.transcript.last
        XCTAssertEqual(lastItem?.title, "History")
        XCTAssertTrue(lastItem?.body.contains("No commands") == true)
    }

    func testHistoryShowsCommandsAfterExecution() async {
        let result = DuckDBExecutionResult(
            binaryPath: "/opt/homebrew/bin/duckdb",
            arguments: [":memory:", "-table", "-c", "SELECT 42;"],
            sql: "SELECT 42;",
            stdout: "42\n",
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

        viewModel.composerText = "/history"
        await viewModel.sendPrompt()

        let historyItems = viewModel.transcript.filter { $0.title == "History" }
        XCTAssertFalse(historyItems.isEmpty)
        XCTAssertTrue(historyItems.last?.body.contains("Recent Commands") == true)
    }

    func testImportDuplicateSourceDoesNotAdd() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/prices.parquet"))
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/prices.parquet"))

        // Should still have only one source (no duplicates)
        XCTAssertEqual(viewModel.sources.count, 1)
    }

    func testUpdateDefaultProviderUpdatesSettings() {
        let sessionStore = MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: []))
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: sessionStore,
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.updateDefaultProvider(.gemini)
        XCTAssertEqual(viewModel.selectedProvider, .gemini)
        XCTAssertEqual(sessionStore.lastSaved?.settings.defaultProvider, .gemini)
    }

    func testUpdateAuthModeUpdatesSettings() {
        let sessionStore = MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: []))
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: sessionStore,
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.updateAuthMode(.apiKey, for: .claude)
        let pref = viewModel.preference(for: .claude)
        XCTAssertEqual(pref.authMode, .apiKey)
    }

    func testUpdateCustomModelUpdatesSettings() {
        let sessionStore = MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: []))
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: sessionStore,
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.updateCustomModel("opus", for: .claude)
        let pref = viewModel.preference(for: .claude)
        XCTAssertEqual(pref.customModel, "opus")
    }

    func testSaveAndRemoveAPIKey() {
        let secretStore = MemorySecretStore()
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: secretStore,
            environment: ["PATH": "/bin"]
        )

        viewModel.saveAPIKey("test-key-123", for: .claude)
        XCTAssertTrue(viewModel.hasStoredAPIKey(for: .claude))

        viewModel.removeAPIKey(for: .claude)
        XCTAssertFalse(viewModel.hasStoredAPIKey(for: .claude))
    }

    func testSaveEmptyAPIKeyIsIgnored() {
        let secretStore = MemorySecretStore()
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: secretStore,
            environment: ["PATH": "/bin"]
        )

        viewModel.saveAPIKey("  ", for: .claude)
        XCTAssertFalse(viewModel.hasStoredAPIKey(for: .claude))
    }

    func testClearConversationResetsTranscript() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [
                TranscriptItem(role: .user, title: "You", body: "some text"),
                TranscriptItem(role: .assistant, title: "A", body: "reply"),
            ])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.clearConversation()

        XCTAssertEqual(viewModel.transcript.count, 1)
        XCTAssertNil(viewModel.lastExecution)
    }

    func testReopenSetupNavigatesToSetup() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.reopenSetup()

        XCTAssertTrue(viewModel.isSetupFlowPresented)
        XCTAssertEqual(viewModel.selectedDestination, .setup)
    }

    func testMetalSnapshotIsRunningState() async {
        let result = DuckDBExecutionResult(
            binaryPath: "/opt/homebrew/bin/duckdb",
            arguments: [":memory:", "-table", "-c", "SELECT 1;"],
            sql: "SELECT 1;",
            stdout: "1\n",
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

        // Before any execution
        XCTAssertFalse(viewModel.metalSnapshot.isRunning)
        XCTAssertEqual(viewModel.metalSnapshot.executionState, .idle)
    }

    func testSearchTranscriptNoMatchReturnsEmpty() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [
                TranscriptItem(role: .assistant, title: "A", body: "Hello world"),
            ])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.searchTranscript(query: "zxcvbnm")
        XCTAssertTrue(viewModel.searchResults.isEmpty)
    }

    func testExportTranscriptCopiesToClipboard() async {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [
                TranscriptItem(role: .assistant, title: "Welcome", body: "Hello"),
                TranscriptItem(role: .user, title: "You", body: "Hi there"),
            ])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.composerText = "/export"
        await viewModel.sendPrompt()

        let exported = viewModel.transcript.filter { $0.title == "Exported" }
        XCTAssertFalse(exported.isEmpty)
        XCTAssertTrue(exported.last?.body.contains("clipboard") == true)
    }

    func testFormatTranscriptAsMarkdownIncludesSQL() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [
                TranscriptItem(role: .assistant, title: "Preview", body: "Running query",
                               kind: .commandPreview(sql: "SELECT 42;", sourceName: "test.duckdb")),
                TranscriptItem(role: .assistant, title: "Result", body: "Done",
                               kind: .commandResult(exitCode: 0, stdout: "42\n", stderr: "")),
            ])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        let markdown = viewModel.formatTranscriptAsMarkdown()
        XCTAssertTrue(markdown.contains("SELECT 42;"))
        XCTAssertTrue(markdown.contains("test.duckdb"))
        XCTAssertTrue(markdown.contains("42\n"))
    }

    func testStatusCommandShowsWorkspaceInfo() async {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/test.parquet"))

        viewModel.composerText = "/status"
        await viewModel.sendPrompt()

        let statusItems = viewModel.transcript.filter { $0.title == "Status" }
        XCTAssertFalse(statusItems.isEmpty)
        let body = statusItems.last!.body
        XCTAssertTrue(body.contains("Sources: 1"))
        XCTAssertTrue(body.contains("test.parquet"))
        XCTAssertTrue(body.contains("Claude"))
    }

    func testPromptChipsReturnedForSelectedSource() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        // No source — generic chips
        XCTAssertFalse(viewModel.promptChips.isEmpty)

        // With source
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/test.parquet"))
        let chips = viewModel.promptChips
        XCTAssertTrue(chips.contains(where: { $0.title.contains("Preview") }))
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

    func testVersionCommandShowsVersionInfo() async {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.composerText = "/version"
        await viewModel.sendPrompt()

        let versionItems = viewModel.transcript.filter { $0.title == "Version" }
        XCTAssertFalse(versionItems.isEmpty)
        XCTAssertTrue(versionItems.last?.body.contains("Sift") == true)
    }

    func testSelectSourceSwitchesActiveSource() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/a.parquet"))
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/b.duckdb"))

        let sourceA = viewModel.sources.first(where: { $0.displayName == "a.parquet" })!
        viewModel.selectSource(sourceA)

        XCTAssertEqual(viewModel.selectedSource, sourceA)
        XCTAssertEqual(viewModel.selectedDestination, .assistant)
    }

    func testEmptyPromptIsIgnored() async {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        let countBefore = viewModel.transcript.count
        viewModel.composerText = "   "
        await viewModel.sendPrompt()

        XCTAssertEqual(viewModel.transcript.count, countBefore)
    }

    func testSendPromptClearsComposerText() async {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.composerText = "/help"
        await viewModel.sendPrompt()

        XCTAssertEqual(viewModel.composerText, "")
    }

    func testTriggerPromptSetsComposerTextAndSends() async {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        await viewModel.triggerPrompt("/help")

        XCTAssertEqual(viewModel.composerText, "")
        XCTAssertTrue(viewModel.transcript.contains(where: { $0.body.contains("Sift Commands") }))
    }

    func testRequestComposerFocusIncrementsID() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        let before = viewModel.composerFocusRequestID
        viewModel.requestComposerFocus()
        XCTAssertEqual(viewModel.composerFocusRequestID, before + 1)
    }

    func testMetalSnapshotSourceCountReflectsImports() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        XCTAssertEqual(viewModel.metalSnapshot.sourceCount, 0)

        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/a.parquet"))
        XCTAssertEqual(viewModel.metalSnapshot.sourceCount, 1)

        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/b.csv"))
        XCTAssertEqual(viewModel.metalSnapshot.sourceCount, 2)
    }

    func testBatchImportImportsMultipleSources() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        let urls = [
            URL(fileURLWithPath: "/tmp/a.parquet"),
            URL(fileURLWithPath: "/tmp/b.csv"),
            URL(fileURLWithPath: "/tmp/c.json"),
        ]

        let count = viewModel.importSources(urls: urls)
        XCTAssertEqual(count, 3)
        XCTAssertEqual(viewModel.sources.count, 3)
        XCTAssertNotNil(viewModel.selectedSource)
    }

    func testBatchImportSkipsUnsupportedFiles() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        let urls = [
            URL(fileURLWithPath: "/tmp/a.parquet"),
            URL(fileURLWithPath: "/tmp/b.xlsx"),
            URL(fileURLWithPath: "/tmp/c.txt"),
        ]

        let count = viewModel.importSources(urls: urls)
        XCTAssertEqual(count, 1)
        XCTAssertEqual(viewModel.sources.count, 1)
    }

    func testBatchImportSkipsDuplicates() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/a.parquet"))

        let urls = [
            URL(fileURLWithPath: "/tmp/a.parquet"),
            URL(fileURLWithPath: "/tmp/b.csv"),
        ]

        let count = viewModel.importSources(urls: urls)
        XCTAssertEqual(count, 1) // Only b.csv is new
        XCTAssertEqual(viewModel.sources.count, 2)
    }

    func testBatchImportReturnsZeroForEmptyArray() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        let count = viewModel.importSources(urls: [])
        XCTAssertEqual(count, 0)
    }

    func testProviderStatusForKnownProvider() {
        let secretStore = MemorySecretStore(keys: [.claude: "key"])
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: secretStore,
            environment: ["PATH": "/bin"]
        )

        let status = viewModel.status(for: .claude)
        XCTAssertNotNil(status)
        XCTAssertEqual(status?.provider, .claude)
    }

    func testRunRawDuckDBCommandEmptyIsIgnored() async {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.manualDuckDBArguments = "  "
        let countBefore = viewModel.transcript.count

        await viewModel.runRawDuckDBCommand()

        XCTAssertEqual(viewModel.transcript.count, countBefore)
    }

    func testUndoRemovesLastUserMessageAndResponses() async {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "Some response")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [
                TranscriptItem(role: .assistant, title: "A", body: "Welcome"),
            ])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        // Send a message that will get a provider response
        viewModel.composerText = "Tell me something"
        await viewModel.sendPrompt()

        let countBeforeUndo = viewModel.transcript.count
        XCTAssertTrue(countBeforeUndo >= 3) // Welcome + user message + response

        viewModel.composerText = "/undo"
        await viewModel.sendPrompt()

        // Should have removed the user message and response, and added "Undone" message
        XCTAssertTrue(viewModel.transcript.contains(where: { $0.title == "Undone" }))
    }

    func testUndoWithNoUserMessagesShowsGuidance() async {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [
                TranscriptItem(role: .assistant, title: "A", body: "Welcome"),
            ])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.composerText = "/undo"
        await viewModel.sendPrompt()

        XCTAssertTrue(viewModel.transcript.contains(where: { $0.title == "Nothing to Undo" }))
    }

    func testBookmarkWithNoCommandsShowsGuidance() async {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.composerText = "/bookmark"
        await viewModel.sendPrompt()

        let lastItem = viewModel.transcript.last
        XCTAssertEqual(lastItem?.title, "Nothing to Bookmark")
    }

    func testBookmarkSavesCommandAfterExecution() async {
        let result = DuckDBExecutionResult(
            binaryPath: "/opt/homebrew/bin/duckdb",
            arguments: [":memory:", "-table", "-c", "SELECT 42;"],
            sql: "SELECT 42;",
            stdout: "42\n",
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

        viewModel.composerText = "/bookmark"
        await viewModel.sendPrompt()

        XCTAssertEqual(viewModel.settings.bookmarks.count, 1)
        XCTAssertTrue(viewModel.transcript.contains(where: { $0.title == "Bookmarked" }))
    }

    func testBookmarkDuplicatePrevented() async {
        let result = DuckDBExecutionResult(
            binaryPath: "/opt/homebrew/bin/duckdb",
            arguments: [":memory:", "-table", "-c", "SELECT 42;"],
            sql: "SELECT 42;",
            stdout: "42\n",
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

        viewModel.composerText = "/bookmark"
        await viewModel.sendPrompt()

        viewModel.composerText = "/bookmark"
        await viewModel.sendPrompt()

        XCTAssertEqual(viewModel.settings.bookmarks.count, 1)
        XCTAssertTrue(viewModel.transcript.contains(where: { $0.title == "Already Bookmarked" }))
    }

    func testShowBookmarksWithNoBookmarks() async {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.composerText = "/bookmarks"
        await viewModel.sendPrompt()

        let lastItem = viewModel.transcript.last
        XCTAssertEqual(lastItem?.title, "Bookmarks")
        XCTAssertTrue(lastItem?.body.contains("No bookmarks") == true)
    }

    func testTranscriptItemsForRoleFilters() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [
                TranscriptItem(role: .assistant, title: "A", body: "Hello"),
                TranscriptItem(role: .user, title: "You", body: "Hi"),
                TranscriptItem(role: .assistant, title: "A", body: "World"),
                TranscriptItem(role: .system, title: "Sys", body: "Info"),
            ])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        XCTAssertEqual(viewModel.transcriptItems(for: .assistant).count, 2)
        XCTAssertEqual(viewModel.transcriptItems(for: .user).count, 1)
        XCTAssertEqual(viewModel.transcriptItems(for: .system).count, 1)
    }

    func testCommandCountReflectsResults() async {
        let result = DuckDBExecutionResult(
            binaryPath: "/opt/homebrew/bin/duckdb",
            arguments: [":memory:", "-table", "-c", "SELECT 1;"],
            sql: "SELECT 1;",
            stdout: "1\n",
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

        XCTAssertEqual(viewModel.commandCount, 0)

        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/prices.parquet"))
        await viewModel.triggerPrompt("Preview this parquet file")

        XCTAssertEqual(viewModel.commandCount, 1)
    }

    func testStatsCommandShowsSessionStats() async {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [
                TranscriptItem(role: .assistant, title: "A", body: "Welcome"),
                TranscriptItem(role: .user, title: "You", body: "Hi"),
            ])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/data.parquet"))

        viewModel.composerText = "/stats"
        await viewModel.sendPrompt()

        let statsItems = viewModel.transcript.filter { $0.title == "Session Stats" }
        XCTAssertFalse(statsItems.isEmpty)
        let body = statsItems.last!.body
        XCTAssertTrue(body.contains("Sources: 1"))
        XCTAssertTrue(body.contains("User messages:"))
    }

    func testUserAndSystemMessageCounts() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [
                TranscriptItem(role: .user, title: "You", body: "Q1"),
                TranscriptItem(role: .assistant, title: "A", body: "R1"),
                TranscriptItem(role: .user, title: "You", body: "Q2"),
                TranscriptItem(role: .system, title: "Sys", body: "Info"),
            ])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        XCTAssertEqual(viewModel.userMessageCount, 2)
        XCTAssertEqual(viewModel.systemMessageCount, 1)
    }

    func testSortedSourcesByName() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/zebra.parquet"))
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/alpha.csv"))
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/mike.json"))

        let sorted = viewModel.sortedSourcesByName
        XCTAssertEqual(sorted.map(\.displayName), ["alpha.csv", "mike.json", "zebra.parquet"])
    }

    func testSortedSourcesByDateMostRecentFirst() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/first.parquet"))
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/second.csv"))
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/third.json"))

        let sorted = viewModel.sortedSourcesByDate
        // Most recently added should be first
        XCTAssertEqual(sorted.first?.displayName, "third.json")
    }

    func testDiagnosticsDrawerStartsClosed() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        XCTAssertFalse(viewModel.isDiagnosticsDrawerPresented)
    }

    func testMetalSnapshotAllDestinations() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.selectedDestination = .assistant
        XCTAssertEqual(viewModel.metalSnapshot.destination, .assistant)

        viewModel.selectedDestination = .transcripts
        XCTAssertEqual(viewModel.metalSnapshot.destination, .transcripts)

        viewModel.selectedDestination = .setup
        XCTAssertEqual(viewModel.metalSnapshot.destination, .setup)

        viewModel.selectedDestination = .settings
        XCTAssertEqual(viewModel.metalSnapshot.destination, .settings)
    }

    func testMetalSnapshotFailureState() async {
        let result = DuckDBExecutionResult(
            binaryPath: "/opt/homebrew/bin/duckdb",
            arguments: [":memory:", "-table", "-c", "INVALID;"],
            sql: "INVALID;",
            stdout: "",
            stderr: "Error: invalid",
            exitCode: 1,
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

        XCTAssertEqual(viewModel.metalSnapshot.executionState, .failure)
    }

    func testMetalSnapshotCommandDurationIsPositive() async {
        let start = Date()
        let end = start.addingTimeInterval(0.5) // 500ms
        let result = DuckDBExecutionResult(
            binaryPath: "/opt/homebrew/bin/duckdb",
            arguments: [":memory:"],
            sql: "SELECT 1;",
            stdout: "1\n",
            stderr: "",
            exitCode: 0,
            startedAt: start,
            endedAt: end
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

        XCTAssertGreaterThan(viewModel.metalSnapshot.commandDurationMilliseconds, 0)
        XCTAssertGreaterThan(viewModel.metalSnapshot.commandOutputBytes, 0)
    }

    func testCompleteSetupWithCLIAuthMode() {
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
            defaultProvider: .claude,
            authMode: .localCLI,
            model: "sonnet",
            apiKey: ""
        )

        XCTAssertFalse(viewModel.requiresInitialSetup)
        XCTAssertFalse(viewModel.isSetupFlowPresented)
        XCTAssertEqual(viewModel.selectedDestination, .assistant)
        // No API key should be stored for CLI mode with empty key
        XCTAssertFalse(viewModel.hasStoredAPIKey(for: .claude))
    }

    func testSendPromptWithExecutorNilShowsDuckDBUnavailable() async {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/prices.parquet"))

        await viewModel.triggerPrompt("Preview this parquet file")

        XCTAssertTrue(viewModel.transcript.contains(where: { $0.title == "DuckDB Unavailable" }))
    }

    func testRunRawDuckDBWithExecutorNilShowsUnavailable() async {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.composerText = "/duckdb --version"
        await viewModel.sendPrompt()

        XCTAssertTrue(viewModel.transcript.contains(where: { $0.title == "DuckDB Unavailable" }))
    }

    func testProviderErrorAppendsToTranscript() async {
        struct FailingResponder: ProviderResponding {
            func respond(prompt: String, source: DataSource?, transcript: [TranscriptItem], settings: AppSettings, providerStatuses: [ProviderStatus]) async throws -> ProviderChatResponse {
                throw ProviderChatError.processFailure("Connection timed out")
            }
            func generateSQL(prompt: String, source: DataSource, transcript: [TranscriptItem], settings: AppSettings, providerStatuses: [ProviderStatus]) async throws -> ProviderSQLResponse {
                throw ProviderChatError.processFailure("Connection timed out")
            }
        }

        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: FailingResponder(),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.composerText = "Explain something complex"
        await viewModel.sendPrompt()

        XCTAssertTrue(viewModel.transcript.contains(where: { $0.title == "Provider Error" }))
    }

    func testNLQueryWithExecutorNilShowsUnavailable() async {
        let sqlResponse = ProviderSQLResponse(
            provider: .claude,
            sql: "SELECT * FROM trades;",
            explanation: "Fetching trades."
        )

        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(
                response: .init(provider: .claude, text: "ignored"),
                sqlResponse: sqlResponse
            ),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/market.duckdb"))

        await viewModel.triggerPrompt("show me the trades")

        XCTAssertTrue(viewModel.transcript.contains(where: { $0.title == "DuckDB Unavailable" }))
    }

    // MARK: - Tab completion

    func testCommandCompletionsForSlashH() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.composerText = "/h"
        let completions = viewModel.commandCompletions
        XCTAssertTrue(completions.contains(where: { $0.command == "/help" }))
        XCTAssertTrue(completions.contains(where: { $0.command == "/history" }))
    }

    func testCommandCompletionsForNonCommandReturnsEmpty() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.composerText = "select * from"
        XCTAssertTrue(viewModel.commandCompletions.isEmpty)
    }

    // MARK: - Cancellation

    func testCancelWhenNotRunningDoesNothing() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        let countBefore = viewModel.transcript.count
        viewModel.cancelRunningCommand()

        // Should not add any transcript items when not running
        XCTAssertEqual(viewModel.transcript.count, countBefore)
        XCTAssertFalse(viewModel.isCancelled)
    }

    func testIsCancelledResetsOnNewPrompt() async {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        // Manually set cancelled state
        // Then send a new prompt to reset it
        viewModel.composerText = "/help"
        await viewModel.sendPrompt()

        XCTAssertFalse(viewModel.isCancelled)
    }

    func testInitialTranscriptHasWelcomeMessage() {
        let items = SiftViewModel.initialTranscript
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.role, .assistant)
        XCTAssertTrue(items.first?.body.contains("Welcome") == true)
    }
}

// MARK: - SidebarDestination

@MainActor
final class SidebarDestinationTests: XCTestCase {
    func testAllCasesExist() {
        let cases = SidebarDestination.allCases
        XCTAssertTrue(cases.contains(.assistant))
        XCTAssertTrue(cases.contains(.transcripts))
        XCTAssertTrue(cases.contains(.setup))
        XCTAssertTrue(cases.contains(.settings))
        XCTAssertEqual(cases.count, 4)
    }

    func testRawValues() {
        XCTAssertEqual(SidebarDestination.assistant.rawValue, "Assistant")
        XCTAssertEqual(SidebarDestination.settings.rawValue, "Settings")
    }

    func testIdentifiable() {
        XCTAssertEqual(SidebarDestination.assistant.id, "Assistant")
    }
}
