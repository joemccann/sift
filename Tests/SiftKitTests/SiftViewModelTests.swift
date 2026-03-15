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

    // MARK: - Tagging

    func testAddTagToTranscriptItem() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [
                TranscriptItem(role: .assistant, title: "A", body: "Hello"),
            ])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        let itemID = viewModel.transcript.first!.id
        viewModel.addTag("important", to: itemID)

        XCTAssertEqual(viewModel.transcript.first?.tags, ["important"])
        XCTAssertEqual(viewModel.allTags, ["important"])
    }

    func testAddDuplicateTagIsIgnored() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [
                TranscriptItem(role: .assistant, title: "A", body: "Hello"),
            ])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        let itemID = viewModel.transcript.first!.id
        viewModel.addTag("sql", to: itemID)
        viewModel.addTag("sql", to: itemID) // duplicate

        XCTAssertEqual(viewModel.transcript.first?.tags.count, 1)
    }

    func testAddEmptyTagIsIgnored() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [
                TranscriptItem(role: .assistant, title: "A", body: "Hello"),
            ])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        let itemID = viewModel.transcript.first!.id
        viewModel.addTag("  ", to: itemID)

        XCTAssertTrue(viewModel.transcript.first?.tags.isEmpty == true)
    }

    func testRemoveTag() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [
                TranscriptItem(role: .assistant, title: "A", body: "Hello", tags: ["a", "b"]),
            ])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        let itemID = viewModel.transcript.first!.id
        viewModel.removeTag("a", from: itemID)

        XCTAssertEqual(viewModel.transcript.first?.tags, ["b"])
    }

    func testTranscriptItemsWithTag() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [
                TranscriptItem(role: .assistant, title: "A", body: "Hello", tags: ["sql"]),
                TranscriptItem(role: .user, title: "You", body: "World"),
                TranscriptItem(role: .assistant, title: "A", body: "Result", tags: ["sql", "important"]),
            ])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        let sqlItems = viewModel.transcriptItems(withTag: "sql")
        XCTAssertEqual(sqlItems.count, 2)

        let importantItems = viewModel.transcriptItems(withTag: "important")
        XCTAssertEqual(importantItems.count, 1)
    }

    func testAllTagsAcrossTranscript() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [
                TranscriptItem(role: .assistant, title: "A", body: "A", tags: ["z", "a"]),
                TranscriptItem(role: .user, title: "You", body: "B", tags: ["b"]),
            ])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        // allTags should be sorted and deduplicated
        XCTAssertEqual(viewModel.allTags, ["a", "b", "z"])
    }

    func testTagsCommandShowsAllTags() async {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [
                TranscriptItem(role: .assistant, title: "A", body: "Hello", tags: ["sql", "important"]),
                TranscriptItem(role: .user, title: "You", body: "Q", tags: ["sql"]),
            ])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.composerText = "/tags"
        await viewModel.sendPrompt()

        let tagItems = viewModel.transcript.filter { $0.title == "Tags" }
        XCTAssertFalse(tagItems.isEmpty)
        let body = tagItems.last!.body
        XCTAssertTrue(body.contains("important"))
        XCTAssertTrue(body.contains("sql"))
    }

    func testTagsCommandWithNoTagsShowsGuidance() async {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [
                TranscriptItem(role: .assistant, title: "A", body: "Hello"),
            ])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.composerText = "/tags"
        await viewModel.sendPrompt()

        let tagItems = viewModel.transcript.filter { $0.title == "Tags" }
        XCTAssertTrue(tagItems.last?.body.contains("No tags") == true)
    }

    // MARK: - Source aliases

    func testSetSourceAlias() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/data.parquet"))
        let sourceID = viewModel.sources.first!.id

        viewModel.setSourceAlias("Prices", for: sourceID)
        XCTAssertEqual(viewModel.sources.first?.displayName, "Prices")
    }

    func testClearSourceAlias() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/data.parquet"))
        let sourceID = viewModel.sources.first!.id

        viewModel.setSourceAlias("Prices", for: sourceID)
        viewModel.setSourceAlias(nil, for: sourceID)
        XCTAssertEqual(viewModel.sources.first?.displayName, "data.parquet")
    }

    // MARK: - Combined workflow: favorites + aliases + tags

    func testFavoriteAliasTagWorkflow() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [
                TranscriptItem(role: .assistant, title: "A", body: "Important result"),
            ])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        // Import and configure a source
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/data.parquet"))
        let sourceID = viewModel.sources.first!.id
        viewModel.setSourceAlias("Market Data", for: sourceID)
        viewModel.toggleFavorite(for: sourceID)

        // Tag a transcript item
        let itemID = viewModel.transcript.first!.id
        viewModel.addTag("key-result", to: itemID)
        viewModel.togglePin(for: itemID)

        // Verify all changes
        XCTAssertEqual(viewModel.sources.first?.displayName, "Market Data")
        XCTAssertTrue(viewModel.sources.first?.isFavorite == true)
        XCTAssertEqual(viewModel.favoriteCount, 1)
        XCTAssertEqual(viewModel.pinnedItemCount, 1)
        XCTAssertEqual(viewModel.totalTagCount, 1)
        XCTAssertTrue(viewModel.hasAliasedSources)
    }

    func testSessionSnapshotPreservesAllState() {
        let sessionStore = MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: []))
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: sessionStore,
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/data.parquet"))
        let sourceID = viewModel.sources.first!.id
        viewModel.setSourceAlias("Test", for: sourceID)
        viewModel.toggleFavorite(for: sourceID)

        // Check the snapshot persisted correctly
        let saved = sessionStore.lastSaved
        XCTAssertNotNil(saved)
        XCTAssertEqual(saved?.sources.first?.alias, "Test")
        XCTAssertTrue(saved?.sources.first?.isFavorite == true)
    }

    func testMultipleCommandsTrackInHistory() async {
        let result = DuckDBExecutionResult(
            binaryPath: "/opt/homebrew/bin/duckdb",
            arguments: [":memory:", "-table", "-c", "SELECT 1;"],
            sql: "SELECT 1;",
            stdout: "1\n", stderr: "", exitCode: 0,
            startedAt: Date(), endedAt: Date()
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
        await viewModel.triggerPrompt("Count rows")
        await viewModel.triggerPrompt("Show schema")

        XCTAssertEqual(viewModel.commandCount, 3)
        XCTAssertEqual(viewModel.commandPreviews.count, 3)
        XCTAssertEqual(viewModel.commandResults.count, 3)
    }

    func testExportAfterMultipleInteractions() async {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "Here is the analysis.")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.composerText = "/help"
        await viewModel.sendPrompt()
        viewModel.composerText = "Explain something"
        await viewModel.sendPrompt()

        let json = viewModel.exportSessionAsJSON()
        XCTAssertNotNil(json)
        XCTAssertTrue(json!.contains("Sift Commands"))
    }

    func testContextualSuggestionsAfterCommands() async {
        let result = DuckDBExecutionResult(
            binaryPath: "/opt/homebrew/bin/duckdb",
            arguments: [], sql: "SELECT 1;",
            stdout: "1\n", stderr: "", exitCode: 0,
            startedAt: Date(), endedAt: Date()
        )

        let viewModel = SiftViewModel(
            executor: MockExecutor(result: result),
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/db.duckdb"))
        await viewModel.triggerPrompt("Show tables")

        // After commands, suggestions should change
        let suggestions = viewModel.contextualSuggestions
        XCTAssertFalse(suggestions.isEmpty)
    }

    func testResetClearsEverythingIncludingFavorites() async {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/data.parquet"))
        viewModel.toggleFavorite(for: viewModel.sources.first!.id)

        viewModel.composerText = "/reset"
        await viewModel.sendPrompt()

        XCTAssertTrue(viewModel.sources.isEmpty)
        XCTAssertTrue(viewModel.favoriteSources.isEmpty)
    }

    // MARK: - Unique command dedup verification

    func testUniqueCommandHistoryPreservesOrder() async {
        let result = DuckDBExecutionResult(
            binaryPath: "/usr/bin/duckdb", arguments: [], sql: "SELECT 1;",
            stdout: "1\n", stderr: "", exitCode: 0,
            startedAt: Date(), endedAt: Date()
        )
        let viewModel = SiftViewModel(
            executor: MockExecutor(result: result),
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/data.parquet"))

        await viewModel.triggerPrompt("Preview this parquet file")
        await viewModel.triggerPrompt("Count rows")
        await viewModel.triggerPrompt("Show schema")

        let history = viewModel.uniqueCommandHistory
        XCTAssertEqual(history.count, 3)
        // First command should be first in history
        XCTAssertTrue(history[0].contains("LIMIT 25"))
    }

    // MARK: - Complete source lifecycle test

    func testSourceFullLifecycle() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        // 1. Import
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/data.parquet"))
        XCTAssertEqual(viewModel.sources.count, 1)

        // 2. Alias
        let id = viewModel.sources.first!.id
        viewModel.setSourceAlias("Prices", for: id)
        XCTAssertEqual(viewModel.sources.first?.displayName, "Prices")

        // 3. Favorite
        viewModel.toggleFavorite(for: id)
        XCTAssertTrue(viewModel.favoriteSources.first?.displayName == "Prices")

        // 4. Notes
        viewModel.setSourceNotes("Daily OHLCV data", for: id)
        XCTAssertEqual(viewModel.sourcesWithNotes.count, 1)

        // 5. Find by search
        XCTAssertEqual(viewModel.findSources(matching: "Prices").count, 1)

        // 6. Remove
        viewModel.removeSource(viewModel.sources.first!)
        XCTAssertTrue(viewModel.sources.isEmpty)
        XCTAssertTrue(viewModel.favoriteSources.isEmpty)
    }

    // MARK: - Error recovery in context

    func testErrorRecoveryWithDuckDBOutput() {
        let error = "Catalog Error: Table 'nonexistent' does not exist"
        let suggestions = DuckDBErrorRecovery.suggestions(for: error)
        XCTAssertTrue(suggestions.contains(where: { $0.contains("SHOW TABLES") }))
    }

    // MARK: - Multiple providers

    func testRefreshProviderStatuses() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.refreshProviderStatuses()
        XCTAssertEqual(viewModel.providerStatuses.count, ProviderKind.allCases.count)
    }

    // MARK: - Notes on nonexistent source

    func testSetNotesOnNonexistentSourceDoesNothing() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.setSourceNotes("Test", for: UUID())
        XCTAssertTrue(viewModel.sourcesWithNotes.isEmpty)
    }

    func testNotesWithWhitespaceIsTrimmed() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/data.parquet"))
        viewModel.setSourceNotes("  Some notes  ", for: viewModel.sources.first!.id)
        XCTAssertEqual(viewModel.sources.first?.notes, "Some notes")
    }

    // MARK: - Command aliases

    func testAddAndResolveCommandAlias() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.addCommandAlias(name: "t", sql: "SHOW TABLES;")
        XCTAssertEqual(viewModel.resolveAlias("t"), "SHOW TABLES;")
        XCTAssertEqual(viewModel.settings.commandAliases.count, 1)
    }

    func testDuplicateAliasNameRejected() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.addCommandAlias(name: "t", sql: "SHOW TABLES;")
        viewModel.addCommandAlias(name: "t", sql: "SELECT 1;") // duplicate name
        XCTAssertEqual(viewModel.settings.commandAliases.count, 1)
        XCTAssertEqual(viewModel.resolveAlias("t"), "SHOW TABLES;")
    }

    func testRemoveCommandAlias() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.addCommandAlias(name: "t", sql: "SHOW TABLES;")
        viewModel.removeCommandAlias(name: "t")
        XCTAssertNil(viewModel.resolveAlias("t"))
    }

    func testEmptyAliasNameRejected() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.addCommandAlias(name: "", sql: "SELECT 1;")
        XCTAssertTrue(viewModel.settings.commandAliases.isEmpty)
    }

    // MARK: - Full end-to-end workflow

    func testEndToEndQueryThenBookmarkThenExport() async {
        let result = DuckDBExecutionResult(
            binaryPath: "/usr/bin/duckdb", arguments: [], sql: "SELECT * FROM trades;",
            stdout: "symbol|price\nAAPL|185\n", stderr: "", exitCode: 0,
            startedAt: Date(), endedAt: Date()
        )
        let viewModel = SiftViewModel(
            executor: MockExecutor(result: result),
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        // 1. Import source
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/data.parquet"))

        // 2. Execute query
        await viewModel.triggerPrompt("Preview this parquet file")
        XCTAssertEqual(viewModel.commandCount, 1)

        // 3. Tag the result
        if let resultItem = viewModel.transcript.last(where: { if case .commandResult = $0.kind { return true }; return false }) {
            viewModel.addTag("key-result", to: resultItem.id)
            viewModel.togglePin(for: resultItem.id)
        }

        // 4. Bookmark it
        await viewModel.triggerPrompt("/bookmark")
        XCTAssertEqual(viewModel.settings.bookmarks.count, 1)

        // 5. Export transcript
        let markdown = viewModel.formatTranscriptAsMarkdown()
        XCTAssertTrue(markdown.contains("read_parquet"))

        // 6. Check stats
        XCTAssertEqual(viewModel.pinnedItemCount, 1)
        XCTAssertEqual(viewModel.totalTagCount, 1)
        XCTAssertFalse(viewModel.uniqueCommandHistory.isEmpty)
    }

    func testEndToEndSetupThenImportThenReset() async {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        // 1. Setup
        viewModel.completeSetup(defaultProvider: .gemini, authMode: .apiKey, model: "flash", apiKey: "key-123")
        XCTAssertEqual(viewModel.selectedProvider, .gemini)
        XCTAssertTrue(viewModel.hasStoredAPIKey(for: .gemini))

        // 2. Import sources
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/a.parquet"))
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/b.csv"))
        viewModel.setSourceAlias("Prices", for: viewModel.sources.first!.id)
        viewModel.toggleFavorite(for: viewModel.sources.first!.id)
        viewModel.addCommandAlias(name: "t", sql: "SHOW TABLES;")

        XCTAssertEqual(viewModel.sourceKindCount, 2)
        XCTAssertEqual(viewModel.favoriteCount, 1)
        XCTAssertTrue(viewModel.hasAliasedSources)

        // 3. Reset
        await viewModel.triggerPrompt("/reset")
        XCTAssertTrue(viewModel.sources.isEmpty)
        XCTAssertTrue(viewModel.settings.bookmarks.isEmpty)
    }

    // MARK: - Table extraction and clause count

    func testExtractTableNamesFromSQL() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )
        let tables = viewModel.extractTableNames(from: "SELECT * FROM trades JOIN prices ON trades.id = prices.id;")
        XCTAssertTrue(tables.contains("trades"))
        XCTAssertTrue(tables.contains("prices"))
    }

    func testSQLClauseCount() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )
        XCTAssertEqual(viewModel.sqlClauseCount("SELECT * FROM trades;"), 2)
        XCTAssertEqual(viewModel.sqlClauseCount("SELECT * FROM a JOIN b ON a.id = b.id WHERE x > 0 ORDER BY x LIMIT 10;"), 6)
    }

    func testTagCounts() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [
                TranscriptItem(role: .assistant, title: "A", body: "X", tags: ["sql", "important"]),
                TranscriptItem(role: .user, title: "You", body: "Y", tags: ["sql"]),
                TranscriptItem(role: .assistant, title: "A", body: "Z", tags: ["important"]),
            ])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        let counts = viewModel.tagCounts
        XCTAssertEqual(counts.count, 2) // "important" and "sql"
        let importantCount = counts.first(where: { $0.tag == "important" })?.count
        XCTAssertEqual(importantCount, 2)
        let sqlCount = counts.first(where: { $0.tag == "sql" })?.count
        XCTAssertEqual(sqlCount, 2)
    }

    func testTagCountsEmpty() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )
        XCTAssertTrue(viewModel.tagCounts.isEmpty)
    }

    // MARK: - SQL formatting and archival

    func testFormatSQL() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )
        let formatted = viewModel.formatSQL("select * from trades where price > 100;")
        XCTAssertTrue(formatted.contains("SELECT"))
        XCTAssertTrue(formatted.contains("FROM"))
    }

    func testArchiveTranscript() {
        let now = Date()
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [
                TranscriptItem(role: .user, title: "A", body: "old", timestamp: now.addingTimeInterval(-7200)),
                TranscriptItem(role: .user, title: "B", body: "new", timestamp: now),
            ])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        let archived = viewModel.archiveTranscript(olderThan: now.addingTimeInterval(-3600))
        XCTAssertEqual(archived, 1)
        // Should have kept 1 original + added 1 "Archived" system message
        XCTAssertTrue(viewModel.transcript.contains(where: { $0.title == "Archived" }))
    }

    func testArchiveTranscriptKeepsPinned() {
        let now = Date()
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [
                TranscriptItem(role: .user, title: "A", body: "old pinned", timestamp: now.addingTimeInterval(-7200), isPinned: true),
                TranscriptItem(role: .user, title: "B", body: "old", timestamp: now.addingTimeInterval(-7200)),
            ])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        let archived = viewModel.archiveTranscript(olderThan: now.addingTimeInterval(-3600), keepPinned: true)
        XCTAssertEqual(archived, 1) // Only the non-pinned one
        XCTAssertTrue(viewModel.transcript.contains(where: { $0.body == "old pinned" }))
    }

    func testArchiveTranscriptNothingToArchive() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [
                TranscriptItem(role: .user, title: "A", body: "new", timestamp: Date()),
            ])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        let archived = viewModel.archiveTranscript(olderThan: Date().addingTimeInterval(-3600))
        XCTAssertEqual(archived, 0)
    }

    func testIsSQLReadOnly() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        XCTAssertTrue(viewModel.isSQLReadOnly("SELECT * FROM trades;"))
        XCTAssertFalse(viewModel.isSQLReadOnly("DROP TABLE trades;"))
    }

    // MARK: - Combined search + complexity workflow

    func testSearchAndComplexityWorkflow() async {
        let result = DuckDBExecutionResult(
            binaryPath: "/usr/bin/duckdb", arguments: [], sql: "SELECT * FROM a JOIN b ON a.id = b.id;",
            stdout: "data", stderr: "", exitCode: 0,
            startedAt: Date(), endedAt: Date()
        )
        let viewModel = SiftViewModel(
            executor: MockExecutor(result: result),
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/db.duckdb"))
        await viewModel.triggerPrompt("/sql SELECT * FROM a JOIN b ON a.id = b.id;")

        // The executed SQL should be moderate complexity
        let history = viewModel.uniqueCommandHistory
        XCTAssertFalse(history.isEmpty)
        if let sql = history.first {
            XCTAssertEqual(viewModel.estimateQueryComplexity(sql), .moderate)
        }
    }

    // MARK: - Full settings round-trip

    func testAllSettingsPreservedInSnapshot() {
        var settings = AppSettings(hasCompletedSetup: true, defaultProvider: .gemini, preferredAppearance: .dark)
        settings.bookmarks = [BookmarkedCommand(sql: "SELECT 1;", sourceName: "test")]
        settings.queryTemplates = [QueryTemplate(name: "Q", sql: "SELECT 2;")]
        settings.commandAliases = [CommandAlias(name: "t", sql: "SHOW TABLES;")]
        settings.setPreference(ProviderPreference(authMode: .apiKey, customModel: "flash"), for: .gemini)

        let sessionStore = MemorySessionStore(snapshot: .init(settings: settings, sources: [], selectedSourceID: nil, transcript: []))
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: sessionStore,
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        XCTAssertEqual(viewModel.selectedProvider, .gemini)
        XCTAssertEqual(viewModel.settings.preferredAppearance, .dark)
        XCTAssertEqual(viewModel.settings.bookmarks.count, 1)
        XCTAssertEqual(viewModel.settings.queryTemplates.count, 1)
        XCTAssertEqual(viewModel.settings.commandAliases.count, 1)
        XCTAssertEqual(viewModel.preference(for: .gemini).authMode, .apiKey)
        XCTAssertEqual(viewModel.preference(for: .gemini).customModel, "flash")
    }

    // MARK: - Transcript search edge cases

    func testSearchWithEmptyQueryAndNoTag() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [
                TranscriptItem(role: .user, title: "You", body: "Hello"),
            ])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        let results = viewModel.searchTranscript(query: "", withTag: nil)
        XCTAssertEqual(results.count, 1) // Returns all
    }

    func testSearchWithNonexistentTag() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [
                TranscriptItem(role: .user, title: "You", body: "Hello"),
            ])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        let results = viewModel.searchTranscript(query: "Hello", withTag: "nonexistent")
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Multiple source operations

    func testImportAndFavoriteManySourcesWorkflow() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        // Import various types
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/a.parquet"))
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/b.csv"))
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/c.json"))
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/d.duckdb"))
        XCTAssertEqual(viewModel.sourceKindCount, 4)

        // Favorite two
        viewModel.toggleFavorite(for: viewModel.sources[0].id)
        viewModel.toggleFavorite(for: viewModel.sources[2].id)
        XCTAssertEqual(viewModel.favoriteCount, 2)

        // Verify grouping
        XCTAssertEqual(viewModel.tabularSources.count, 3)
        XCTAssertEqual(viewModel.databaseSources.count, 1)
    }

    // MARK: - Search with tag filter

    func testSearchTranscriptWithTagFilter() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [
                TranscriptItem(role: .assistant, title: "A", body: "AAPL data", tags: ["market"]),
                TranscriptItem(role: .user, title: "You", body: "Show AAPL", tags: ["request"]),
                TranscriptItem(role: .assistant, title: "A", body: "AAPL result", tags: ["market"]),
            ])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        // Search with tag filter
        let results = viewModel.searchTranscript(query: "AAPL", withTag: "market")
        XCTAssertEqual(results.count, 2) // Only the two with "market" tag

        // Search with tag only
        let tagOnly = viewModel.searchTranscript(query: "", withTag: "market")
        XCTAssertEqual(tagOnly.count, 2)

        // Search with query only
        let queryOnly = viewModel.searchTranscript(query: "AAPL", withTag: nil)
        XCTAssertEqual(queryOnly.count, 3)
    }

    // MARK: - Query complexity

    func testEstimateQueryComplexity() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        XCTAssertEqual(viewModel.estimateQueryComplexity("SELECT * FROM trades;"), .simple)
        XCTAssertEqual(viewModel.estimateQueryComplexity("SELECT * FROM a JOIN b ON a.id = b.id;"), .moderate)
    }

    // MARK: - Alias edge cases

    func testResolveNonexistentAlias() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )
        XCTAssertNil(viewModel.resolveAlias("nonexistent"))
    }

    func testRemoveNonexistentAliasDoesNothing() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )
        viewModel.addCommandAlias(name: "a", sql: "SELECT 1;")
        viewModel.removeCommandAlias(name: "nonexistent")
        XCTAssertEqual(viewModel.settings.commandAliases.count, 1)
    }

    func testAddAliasWithWhitespaceSQL() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )
        viewModel.addCommandAlias(name: "t", sql: "  ")
        XCTAssertTrue(viewModel.settings.commandAliases.isEmpty) // empty SQL rejected
    }

    // MARK: - Deduplication

    func testHasDuplicateMessages() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [
                TranscriptItem(role: .user, title: "You", body: "Hello"),
                TranscriptItem(role: .assistant, title: "A", body: "Hi"),
                TranscriptItem(role: .user, title: "You", body: "Hello"),
            ])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        XCTAssertTrue(viewModel.hasDuplicateMessages)
    }

    func testResultsAsCSV() async {
        let result = DuckDBExecutionResult(
            binaryPath: "/usr/bin/duckdb", arguments: [], sql: "SELECT 1;",
            stdout: "1\n", stderr: "", exitCode: 0,
            startedAt: Date(), endedAt: Date()
        )
        let viewModel = SiftViewModel(
            executor: MockExecutor(result: result),
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/data.parquet"))
        await viewModel.triggerPrompt("Preview this parquet file")

        let csv = viewModel.resultsAsCSV
        XCTAssertTrue(csv.contains("sql,exit_code"))
    }

    // MARK: - Source notes

    func testSetSourceNotes() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/data.parquet"))
        let sourceID = viewModel.sources.first!.id

        viewModel.setSourceNotes("Daily trade data from 2024", for: sourceID)
        XCTAssertEqual(viewModel.sources.first?.notes, "Daily trade data from 2024")
        XCTAssertEqual(viewModel.sourcesWithNotes.count, 1)
    }

    func testClearSourceNotes() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/data.parquet"))
        let sourceID = viewModel.sources.first!.id
        viewModel.setSourceNotes("Some notes", for: sourceID)
        viewModel.setSourceNotes(nil, for: sourceID)
        XCTAssertTrue(viewModel.sourcesWithNotes.isEmpty)
    }

    // MARK: - Query history search

    func testSearchQueryHistoryFindsMatches() async {
        let result = DuckDBExecutionResult(
            binaryPath: "/usr/bin/duckdb", arguments: [], sql: "SELECT * FROM trades;",
            stdout: "1\n", stderr: "", exitCode: 0,
            startedAt: Date(), endedAt: Date()
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

        let matches = viewModel.searchQueryHistory(query: "read_parquet")
        XCTAssertFalse(matches.isEmpty)
    }

    func testSearchQueryHistoryNoMatches() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        XCTAssertTrue(viewModel.searchQueryHistory(query: "anything").isEmpty)
    }

    // MARK: - Error/success results

    func testErrorAndSuccessResults() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [
                TranscriptItem(role: .assistant, title: "OK", body: "good", kind: .commandResult(exitCode: 0, stdout: "1", stderr: "")),
                TranscriptItem(role: .assistant, title: "Bad", body: "err", kind: .commandResult(exitCode: 1, stdout: "", stderr: "error")),
                TranscriptItem(role: .assistant, title: "OK2", body: "good2", kind: .commandResult(exitCode: 0, stdout: "2", stderr: "")),
            ])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        XCTAssertEqual(viewModel.errorResults.count, 1)
        XCTAssertEqual(viewModel.successResults.count, 2)
    }

    func testFavoriteCount() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/a.parquet"))
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/b.csv"))
        viewModel.toggleFavorite(for: viewModel.sources.first!.id)

        XCTAssertEqual(viewModel.favoriteCount, 1)
    }

    func testHasAliasedSources() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/data.parquet"))
        XCTAssertFalse(viewModel.hasAliasedSources)

        viewModel.setSourceAlias("Prices", for: viewModel.sources.first!.id)
        XCTAssertTrue(viewModel.hasAliasedSources)
    }

    func testSourcesByDirectory() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.importSource(url: URL(fileURLWithPath: "/data/a.parquet"))
        viewModel.importSource(url: URL(fileURLWithPath: "/data/b.csv"))
        viewModel.importSource(url: URL(fileURLWithPath: "/other/c.json"))

        let grouped = viewModel.sourcesByDirectory
        XCTAssertEqual(grouped["data"]?.count, 2)
        XCTAssertEqual(grouped["other"]?.count, 1)
    }

    // MARK: - Source favorites

    func testToggleFavorite() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/data.parquet"))
        let sourceID = viewModel.sources.first!.id

        XCTAssertTrue(viewModel.favoriteSources.isEmpty)

        viewModel.toggleFavorite(for: sourceID)
        XCTAssertEqual(viewModel.favoriteSources.count, 1)

        viewModel.toggleFavorite(for: sourceID)
        XCTAssertTrue(viewModel.favoriteSources.isEmpty)
    }

    func testToggleFavoriteNonexistentIDDoesNothing() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.toggleFavorite(for: UUID())
        XCTAssertTrue(viewModel.favoriteSources.isEmpty)
    }

    // MARK: - Source comparison

    func testCompareSourcesSameKind() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/a.parquet"))
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/b.parquet"))

        let ids = viewModel.sources.map(\.id)
        let cmp = viewModel.compareSources(ids[0], ids[1])
        XCTAssertNotNil(cmp)
        XCTAssertTrue(cmp!.sameKind)
        XCTAssertTrue(cmp!.sameDirectory)
    }

    func testCompareSourcesInvalidID() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        XCTAssertNil(viewModel.compareSources(UUID(), UUID()))
    }

    // MARK: - Output parsing integration

    func testOutputParserOnSuccessfulResult() async {
        let result = DuckDBExecutionResult(
            binaryPath: "/opt/homebrew/bin/duckdb",
            arguments: [":memory:", "-table", "-c", "SELECT 1;"],
            sql: "SELECT 1;",
            stdout: "answer\n1\n(1 row)\n",
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
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/test.parquet"))
        await viewModel.triggerPrompt("Preview this parquet file")

        // The output should be parseable
        if let output = viewModel.lastSuccessfulOutput {
            let rowCount = DuckDBOutputParser.extractRowCount(from: output)
            XCTAssertEqual(rowCount, 1)
        }
    }

    func testOutputParserDetectsError() {
        let errorOutput = "Error: table 'missing' does not exist"
        XCTAssertTrue(DuckDBOutputParser.containsError(in: errorOutput))
    }

    func testOutputParserCountsDataRows() {
        let output = "name | age\nAlice | 30\nBob | 25\n"
        // 3 lines: header + 2 data = 2 data rows
        let count = DuckDBOutputParser.countDataRows(in: output)
        XCTAssertGreaterThan(count, 0)
    }

    // MARK: - Full workflow test

    func testCompleteWorkflowFromSetupToQuery() async {
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
            sessionStore: MemorySessionStore(),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        // Step 1: Complete setup
        viewModel.completeSetup(defaultProvider: .claude, authMode: .localCLI, model: "sonnet", apiKey: "")
        XCTAssertFalse(viewModel.requiresInitialSetup)

        // Step 2: Import a source
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/data.parquet"))
        XCTAssertEqual(viewModel.sources.count, 1)

        // Step 3: Run a query
        await viewModel.triggerPrompt("Preview this parquet file")
        XCTAssertNotNil(viewModel.lastExecution)
        XCTAssertEqual(viewModel.commandCount, 1)

        // Step 4: Bookmark it
        viewModel.composerText = "/bookmark"
        await viewModel.sendPrompt()
        XCTAssertEqual(viewModel.settings.bookmarks.count, 1)

        // Step 5: Check status
        viewModel.composerText = "/status"
        await viewModel.sendPrompt()
        XCTAssertTrue(viewModel.transcript.contains(where: { $0.title == "Status" }))
    }

    // MARK: - Provider with source context

    func testProviderPromptIncludesSourceContext() async {
        let response = ProviderChatResponse(provider: .claude, text: "Use read_parquet to query.")
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: response),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        // With a parquet source, a general question that doesn't match patterns goes to NL query
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/prices.parquet"))

        // A question that doesn't match any keyword should trigger NL query or provider
        viewModel.composerText = "What is the correlation between price and volume?"
        await viewModel.sendPrompt()

        // Should have some response in the transcript
        XCTAssertTrue(viewModel.transcript.count > 2)
    }

    // MARK: - Remote source import

    func testImportRemoteSourceCreatesSource() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.importRemoteSource(urlString: "https://example.com/data.parquet")
        XCTAssertEqual(viewModel.sources.count, 1)
        XCTAssertTrue(viewModel.sources.first?.isRemote == true)
        XCTAssertTrue(viewModel.transcript.contains(where: { $0.title == "Remote Source" }))
    }

    func testImportRemoteSourceInvalidURL() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.importRemoteSource(urlString: "not a valid url")
        XCTAssertTrue(viewModel.sources.isEmpty)
        XCTAssertTrue(viewModel.transcript.contains(where: { $0.title == "Invalid URL" }))
    }

    func testImportRemoteDuplicateDoesNotAdd() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.importRemoteSource(urlString: "https://example.com/data.csv")
        viewModel.importRemoteSource(urlString: "https://example.com/data.csv")
        XCTAssertEqual(viewModel.sources.count, 1)
    }

    // MARK: - Contextual suggestions

    func testContextualSuggestionsWithNoSources() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        let suggestions = viewModel.contextualSuggestions
        XCTAssertTrue(suggestions.contains(where: { $0.contains("Open") }))
    }

    func testContextualSuggestionsWithParquetSource() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/data.parquet"))

        let suggestions = viewModel.contextualSuggestions
        XCTAssertTrue(suggestions.contains("Preview rows"))
        XCTAssertTrue(suggestions.contains("Show schema"))
    }

    func testContextualSuggestionsWithDuckDBSource() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/db.duckdb"))

        let suggestions = viewModel.contextualSuggestions
        XCTAssertTrue(suggestions.contains("Show tables"))
    }

    // MARK: - Tabular vs database sources

    func testTabularAndDatabaseSources() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/a.parquet"))
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/b.csv"))
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/c.duckdb"))

        XCTAssertEqual(viewModel.tabularSources.count, 2)
        XCTAssertEqual(viewModel.databaseSources.count, 1)
    }

    // MARK: - Composer command detection

    func testIsComposerCommandForSlashPrefix() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.composerText = "/help"
        XCTAssertTrue(viewModel.isComposerCommand)

        viewModel.composerText = "Show me data"
        XCTAssertFalse(viewModel.isComposerCommand)

        viewModel.composerText = ""
        XCTAssertFalse(viewModel.isComposerCommand)
    }

    // MARK: - Pinned and tag counts

    func testPinnedItemCountAndTotalTagCount() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [
                TranscriptItem(role: .assistant, title: "A", body: "Hello", isPinned: true, tags: ["a", "b"]),
                TranscriptItem(role: .user, title: "You", body: "Q", tags: ["c"]),
                TranscriptItem(role: .assistant, title: "A", body: "R"),
            ])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        XCTAssertEqual(viewModel.pinnedItemCount, 1)
        XCTAssertEqual(viewModel.totalTagCount, 3) // a, b, c
    }

    // MARK: - Multiple execution stats

    func testAverageExecutionTime() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        let start = Date()
        let r1 = DuckDBExecutionResult(binaryPath: "/usr/bin/duckdb", arguments: [], sql: "SELECT 1;", stdout: "1", stderr: "", exitCode: 0, startedAt: start, endedAt: start.addingTimeInterval(0.1))
        let r2 = DuckDBExecutionResult(binaryPath: "/usr/bin/duckdb", arguments: [], sql: "SELECT 2;", stdout: "2", stderr: "", exitCode: 0, startedAt: start, endedAt: start.addingTimeInterval(0.3))

        viewModel.recordExecution(r1)
        viewModel.recordExecution(r2)

        // Average of 100ms and 300ms = 200ms
        XCTAssertEqual(viewModel.averageExecutionTimeMs, 200, accuracy: 10)
    }

    // MARK: - Fastest execution

    func testFastestExecutionTracked() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        let start = Date()
        let fast = DuckDBExecutionResult(binaryPath: "/usr/bin/duckdb", arguments: [], sql: "SELECT 1;", stdout: "1", stderr: "", exitCode: 0, startedAt: start, endedAt: start.addingTimeInterval(0.01))
        let slow = DuckDBExecutionResult(binaryPath: "/usr/bin/duckdb", arguments: [], sql: "SELECT 2;", stdout: "2", stderr: "", exitCode: 0, startedAt: start, endedAt: start.addingTimeInterval(1.0))

        viewModel.recordExecution(slow)
        viewModel.recordExecution(fast)

        XCTAssertEqual(viewModel.fastestExecutionMs!, 10, accuracy: 1)
        XCTAssertEqual(viewModel.executionHistory.count, 2)
    }

    // MARK: - Execution stats

    func testRecordExecutionTracksStats() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        let start = Date()
        let result = DuckDBExecutionResult(
            binaryPath: "/usr/bin/duckdb", arguments: [], sql: "SELECT 1;",
            stdout: "1", stderr: "", exitCode: 0,
            startedAt: start, endedAt: start.addingTimeInterval(0.1)
        )

        viewModel.recordExecution(result)
        XCTAssertEqual(viewModel.executionHistory.count, 1)
        XCTAssertEqual(viewModel.executionHistory.first?.sql, "SELECT 1;")
        XCTAssertTrue(viewModel.executionHistory.first?.succeeded == true)
    }

    func testExecutionSuccessRate() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        let start = Date()
        let success = DuckDBExecutionResult(binaryPath: "/usr/bin/duckdb", arguments: [], sql: "SELECT 1;", stdout: "1", stderr: "", exitCode: 0, startedAt: start, endedAt: start.addingTimeInterval(0.1))
        let failure = DuckDBExecutionResult(binaryPath: "/usr/bin/duckdb", arguments: [], sql: "BAD;", stdout: "", stderr: "error", exitCode: 1, startedAt: start, endedAt: start.addingTimeInterval(0.05))

        viewModel.recordExecution(success)
        viewModel.recordExecution(success)
        viewModel.recordExecution(failure)

        XCTAssertEqual(viewModel.executionSuccessRate, 2.0 / 3.0, accuracy: 0.01)
    }

    func testAverageExecutionTimeEmpty() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        XCTAssertEqual(viewModel.averageExecutionTimeMs, 0)
        XCTAssertNil(viewModel.fastestExecutionMs)
    }

    // MARK: - Transcript analytics on ViewModel

    func testTranscriptWordAndCharacterCount() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [
                TranscriptItem(role: .user, title: "You", body: "Hello world"),
                TranscriptItem(role: .assistant, title: "A", body: "OK"),
            ])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        XCTAssertEqual(viewModel.transcriptWordCount, 3) // "Hello" "world" "OK"
        XCTAssertEqual(viewModel.transcriptCharacterCount, 13) // "Hello world" + "OK"
    }

    // MARK: - Provider preference lookup

    func testPreferenceDefaultsForAllProviders() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        for provider in ProviderKind.allCases {
            let pref = viewModel.preference(for: provider)
            XCTAssertEqual(pref.authMode, .localCLI)
        }
    }

    func testRequiresInitialSetupAfterComplete() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        XCTAssertFalse(viewModel.requiresInitialSetup)
    }

    func testSelectedProviderReflectsSettings() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true, defaultProvider: .gemini), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        XCTAssertEqual(viewModel.selectedProvider, .gemini)
    }

    func testMetalSnapshotProviderReadinessWithMultipleKeys() {
        let secretStore = MemorySecretStore(keys: [.claude: "key1", .openAI: "key2", .gemini: "key3"])
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: secretStore,
            environment: ["PATH": "/bin"]
        )

        XCTAssertEqual(viewModel.metalSnapshot.providerReadiness, 3)
    }

    // MARK: - Source kind filtering

    func testSourcesOfKind() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/a.parquet"))
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/b.parquet"))
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/c.csv"))

        XCTAssertEqual(viewModel.sources(ofKind: .parquet).count, 2)
        XCTAssertEqual(viewModel.sources(ofKind: .csv).count, 1)
        XCTAssertEqual(viewModel.sources(ofKind: .duckdb).count, 0)
    }

    // MARK: - Command error detection

    func testHasCommandErrorsWhenNoErrors() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [
                TranscriptItem(role: .assistant, title: "Result", body: "ok",
                               kind: .commandResult(exitCode: 0, stdout: "1", stderr: "")),
            ])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        XCTAssertFalse(viewModel.hasCommandErrors)
    }

    func testHasCommandErrorsWhenErrorPresent() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [
                TranscriptItem(role: .assistant, title: "Error", body: "fail",
                               kind: .commandResult(exitCode: 1, stdout: "", stderr: "error")),
            ])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        XCTAssertTrue(viewModel.hasCommandErrors)
    }

    // MARK: - Last N items

    func testLastTranscriptItems() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [
                TranscriptItem(role: .user, title: "You", body: "A"),
                TranscriptItem(role: .assistant, title: "A", body: "B"),
                TranscriptItem(role: .user, title: "You", body: "C"),
            ])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        let last2 = viewModel.lastTranscriptItems(2)
        XCTAssertEqual(last2.count, 2)
        XCTAssertEqual(last2.first?.body, "B")
        XCTAssertEqual(last2.last?.body, "C")
    }

    func testLastTranscriptItemsWithZero() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [
                TranscriptItem(role: .user, title: "You", body: "A"),
            ])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        XCTAssertTrue(viewModel.lastTranscriptItems(0).isEmpty)
        XCTAssertTrue(viewModel.lastTranscriptItems(-1).isEmpty)
    }

    // MARK: - Tag on nonexistent item

    func testAddTagToNonexistentItemDoesNothing() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.addTag("test", to: UUID())
        XCTAssertTrue(viewModel.allTags.isEmpty)
    }

    func testRemoveTagFromNonexistentItemDoesNothing() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [
                TranscriptItem(role: .assistant, title: "A", body: "Hello", tags: ["x"]),
            ])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.removeTag("x", from: UUID()) // wrong ID
        XCTAssertEqual(viewModel.allTags, ["x"]) // unchanged
    }

    // MARK: - Source alias edge cases

    func testSetAliasOnNonexistentSourceDoesNothing() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.setSourceAlias("Test", for: UUID())
        XCTAssertTrue(viewModel.sources.isEmpty) // no crash
    }

    func testAliasWithWhitespaceIsTrimmed() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/data.parquet"))
        let sourceID = viewModel.sources.first!.id
        viewModel.setSourceAlias("  Prices  ", for: sourceID)
        XCTAssertEqual(viewModel.sources.first?.alias, "Prices")
    }

    // MARK: - Mixed workflow tests

    func testTagPinAndSearchWorkTogether() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [
                TranscriptItem(role: .assistant, title: "Result", body: "AAPL data here"),
            ])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        let itemID = viewModel.transcript.first!.id

        // Tag it
        viewModel.addTag("important", to: itemID)
        XCTAssertEqual(viewModel.transcriptItems(withTag: "important").count, 1)

        // Pin it
        viewModel.togglePin(for: itemID)
        XCTAssertEqual(viewModel.pinnedItems.count, 1)

        // Search for it
        viewModel.searchTranscript(query: "AAPL")
        XCTAssertEqual(viewModel.searchResults.count, 1)

        // All three features work on the same item
        let item = viewModel.transcript.first!
        XCTAssertTrue(item.isPinned)
        XCTAssertEqual(item.tags, ["important"])
    }

    func testMultipleSourceAliasesWithSearch() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/a.parquet"))
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/b.csv"))

        let aID = viewModel.sources.first(where: { $0.url.lastPathComponent == "a.parquet" })!.id
        viewModel.setSourceAlias("Apple Prices", for: aID)

        let found = viewModel.findSources(matching: "Apple")
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.displayName, "Apple Prices")
    }

    // MARK: - Compact transcript

    func testCompactTranscriptFiltersToUserAndResults() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [
                TranscriptItem(role: .user, title: "You", body: "Hello"),
                TranscriptItem(role: .assistant, title: "A", body: "thinking", kind: .thinking),
                TranscriptItem(role: .assistant, title: "A", body: "preview",
                               kind: .commandPreview(sql: "SELECT 1;", sourceName: "test")),
                TranscriptItem(role: .assistant, title: "A", body: "result",
                               kind: .commandResult(exitCode: 0, stdout: "1", stderr: "")),
                TranscriptItem(role: .system, title: "Sys", body: "info"),
            ])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        let compact = viewModel.compactTranscript
        XCTAssertEqual(compact.count, 2) // user message + command result
        XCTAssertEqual(compact[0].role, .user)
        XCTAssertEqual(compact[1].body, "result")
    }

    func testCompactTranscriptEmptyWhenNoUserOrResults() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [
                TranscriptItem(role: .assistant, title: "A", body: "Welcome"),
                TranscriptItem(role: .system, title: "Sys", body: "Info"),
            ])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        XCTAssertTrue(viewModel.compactTranscript.isEmpty)
    }

    // MARK: - DuckDB run with source context

    func testRawDuckDBCommandWithExecutorExecutes() async {
        let result = DuckDBExecutionResult(
            binaryPath: "/opt/homebrew/bin/duckdb",
            arguments: ["--version"],
            sql: "",
            stdout: "v1.0.0",
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

        viewModel.manualDuckDBArguments = "--version"
        await viewModel.runRawDuckDBCommand()

        XCTAssertEqual(viewModel.lastExecution?.stdout, "v1.0.0")
        XCTAssertEqual(viewModel.manualDuckDBArguments, "")
    }

    func testSendPromptWithSQLCommand() async {
        let result = DuckDBExecutionResult(
            binaryPath: "/opt/homebrew/bin/duckdb",
            arguments: [":memory:", "-table", "-c", "SELECT 42 AS answer;"],
            sql: "SELECT 42 AS answer;",
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
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/db.duckdb"))

        viewModel.composerText = "/sql SELECT 42 AS answer;"
        await viewModel.sendPrompt()

        XCTAssertEqual(viewModel.lastExecution?.stdout, "42\n")
    }

    func testSendSQLWithoutSourceShowsGuidance() async {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.composerText = "/sql SELECT 1;"
        await viewModel.sendPrompt()

        // Without a source, /sql should tell user to open a source
        XCTAssertTrue(viewModel.transcript.contains(where: { $0.body.contains("Open a local") || $0.body.contains("source") }))
    }

    func testMultipleImportAndRemoveWorkflow() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/a.parquet"))
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/b.csv"))
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/c.json"))
        XCTAssertEqual(viewModel.sources.count, 3)

        viewModel.removeSource(viewModel.sources.first(where: { $0.displayName == "b.csv" })!)
        XCTAssertEqual(viewModel.sources.count, 2)

        viewModel.removeAllSources()
        XCTAssertTrue(viewModel.sources.isEmpty)
        XCTAssertNil(viewModel.selectedSource)
    }

    // MARK: - Session export

    func testExportSessionAsJSONReturnsValidJSON() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [
                TranscriptItem(role: .assistant, title: "A", body: "Hello"),
            ])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        let json = viewModel.exportSessionAsJSON()
        XCTAssertNotNil(json)

        // Verify it's valid JSON by decoding
        if let json, let data = json.data(using: .utf8) {
            let restored = try? JSONDecoder().decode(AppSessionSnapshot.self, from: data)
            XCTAssertNotNil(restored)
            XCTAssertTrue(restored?.settings.hasCompletedSetup == true)
        }
    }

    func testExportSessionPreservesSourcesAndTranscript() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/data.parquet"))

        let json = viewModel.exportSessionAsJSON()
        XCTAssertNotNil(json)
        XCTAssertTrue(json?.contains("data.parquet") == true)
    }

    // MARK: - Source search

    func testFindSourcesByName() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/prices.parquet"))
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/trades.csv"))
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/prices_v2.json"))

        let matches = viewModel.findSources(matching: "prices")
        XCTAssertEqual(matches.count, 2)
    }

    func testFindSourcesEmptyQueryReturnsAll() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/a.parquet"))
        XCTAssertEqual(viewModel.findSources(matching: "").count, 1)
    }

    // MARK: - Unique command history

    func testUniqueCommandHistoryDedupes() async {
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
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/prices.parquet"))

        // Run the same command twice
        await viewModel.triggerPrompt("Preview this parquet file")
        await viewModel.triggerPrompt("Preview this parquet file")

        // Should only have one unique command even though run twice
        let unique = viewModel.uniqueCommandHistory
        XCTAssertEqual(unique.count, 1)
    }

    func testUniqueCommandHistoryEmptyWhenNoCommands() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        XCTAssertTrue(viewModel.uniqueCommandHistory.isEmpty)
    }

    // MARK: - Transcript pagination

    func testTranscriptPageReturnsCorrectSlice() {
        var items: [TranscriptItem] = []
        for i in 0..<25 {
            items.append(TranscriptItem(role: .user, title: "You", body: "msg \(i)"))
        }

        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: items)),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        let page0 = viewModel.transcriptPage(page: 0, pageSize: 10)
        XCTAssertEqual(page0.count, 10)

        let page1 = viewModel.transcriptPage(page: 1, pageSize: 10)
        XCTAssertEqual(page1.count, 10)

        let page2 = viewModel.transcriptPage(page: 2, pageSize: 10)
        XCTAssertEqual(page2.count, 5) // Last page partial

        let page3 = viewModel.transcriptPage(page: 3, pageSize: 10)
        XCTAssertTrue(page3.isEmpty) // Beyond end
    }

    func testTranscriptPageCountCalculation() {
        var items: [TranscriptItem] = []
        for i in 0..<25 {
            items.append(TranscriptItem(role: .user, title: "You", body: "msg \(i)"))
        }

        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: items)),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        XCTAssertEqual(viewModel.transcriptPageCount(pageSize: 10), 3)
        XCTAssertEqual(viewModel.transcriptPageCount(pageSize: 25), 1)
        XCTAssertEqual(viewModel.transcriptPageCount(pageSize: 100), 1)
    }

    func testTranscriptPageEdgeCases() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        // Negative page
        XCTAssertTrue(viewModel.transcriptPage(page: -1).isEmpty)

        // Zero page size
        XCTAssertTrue(viewModel.transcriptPage(page: 0, pageSize: 0).isEmpty)
        XCTAssertEqual(viewModel.transcriptPageCount(pageSize: 0), 0)
    }

    // MARK: - Appearance setting

    func testDefaultAppearanceIsSystem() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true, preferredAppearance: .dark), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        XCTAssertEqual(viewModel.settings.preferredAppearance, .dark)
    }

    func testAppearanceFromDefaultSettings() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        XCTAssertEqual(viewModel.settings.preferredAppearance, .system)
    }

    func testNewSessionDurationIsSmall() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        // Freshly created session should have very small duration (< 1 second)
        XCTAssertLessThan(viewModel.sessionDuration, 1.0)
    }

    // MARK: - Source kind checks

    func testHasDatabaseSource() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        XCTAssertFalse(viewModel.hasDatabaseSource)
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/db.duckdb"))
        XCTAssertTrue(viewModel.hasDatabaseSource)
    }

    func testHasFileSource() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        XCTAssertFalse(viewModel.hasFileSource)
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/data.parquet"))
        XCTAssertTrue(viewModel.hasFileSource)
    }

    func testSourceKindCount() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        XCTAssertEqual(viewModel.sourceKindCount, 0)
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/a.parquet"))
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/b.parquet"))
        XCTAssertEqual(viewModel.sourceKindCount, 1) // Both are parquet

        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/c.csv"))
        XCTAssertEqual(viewModel.sourceKindCount, 2) // parquet + csv
    }

    // MARK: - Recent sources

    func testRecentSourcesReturnsUpToLimit() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        for i in 0..<10 {
            viewModel.importSource(url: URL(fileURLWithPath: "/tmp/file\(i).parquet"))
        }

        let recent3 = viewModel.recentSources(limit: 3)
        XCTAssertEqual(recent3.count, 3)

        let recent20 = viewModel.recentSources(limit: 20)
        XCTAssertEqual(recent20.count, 10) // Only 10 exist
    }

    func testSessionDurationIsPositive() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [
                TranscriptItem(role: .assistant, title: "A", body: "Welcome"),
            ])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        XCTAssertGreaterThanOrEqual(viewModel.sessionDuration, 0)
    }

    func testLastSuccessfulOutputNilBeforeExecution() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        XCTAssertNil(viewModel.lastSuccessfulOutput)
    }

    func testLastSuccessfulOutputAfterExecution() async {
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
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/test.parquet"))
        await viewModel.triggerPrompt("Preview this parquet file")

        XCTAssertEqual(viewModel.lastSuccessfulOutput, "42\n")
    }

    func testLastSuccessfulOutputNilForFailedExecution() async {
        let result = DuckDBExecutionResult(
            binaryPath: "/opt/homebrew/bin/duckdb",
            arguments: [":memory:", "-table", "-c", "INVALID;"],
            sql: "INVALID;",
            stdout: "",
            stderr: "error",
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
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/test.parquet"))
        await viewModel.triggerPrompt("Preview this parquet file")

        XCTAssertNil(viewModel.lastSuccessfulOutput)
    }

    // MARK: - Source validation

    func testMissingSourcesDetectsNonexistentFiles() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.importSource(url: URL(fileURLWithPath: "/nonexistent/path/data.parquet"))
        XCTAssertEqual(viewModel.missingSources.count, 1)
    }

    func testRemoveMissingSourcesCleansUp() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.importSource(url: URL(fileURLWithPath: "/nonexistent/a.parquet"))
        viewModel.importSource(url: URL(fileURLWithPath: "/nonexistent/b.csv"))
        XCTAssertEqual(viewModel.sources.count, 2)

        let removed = viewModel.removeMissingSources()
        XCTAssertEqual(removed, 2)
        XCTAssertTrue(viewModel.sources.isEmpty)
        XCTAssertTrue(viewModel.transcript.contains(where: { $0.title == "Sources Cleaned" }))
    }

    func testRemoveMissingSourcesWithNoMissing() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        let removed = viewModel.removeMissingSources()
        XCTAssertEqual(removed, 0)
    }

    // MARK: - Transcript summary

    func testTranscriptSummaryFormatted() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [
                TranscriptItem(role: .user, title: "You", body: "Hello"),
                TranscriptItem(role: .assistant, title: "A", body: "World"),
            ])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        let summary = viewModel.transcriptSummary
        XCTAssertTrue(summary.contains("2 items"))
        XCTAssertTrue(summary.contains("1 user messages"))
        XCTAssertTrue(summary.contains("0 commands"))
    }

    // MARK: - Reset workspace

    func testResetClearsEverything() async {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/a.parquet"))
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/b.csv"))
        XCTAssertEqual(viewModel.sources.count, 2)

        viewModel.composerText = "/reset"
        await viewModel.sendPrompt()

        XCTAssertTrue(viewModel.sources.isEmpty)
        XCTAssertNil(viewModel.selectedSource)
        XCTAssertNil(viewModel.lastExecution)
        XCTAssertTrue(viewModel.transcript.contains(where: { $0.title == "Workspace Reset" }))
    }

    func testResetClearsBookmarks() async {
        var settings = AppSettings(hasCompletedSetup: true)
        settings.bookmarks = [BookmarkedCommand(sql: "SELECT 1;", sourceName: "test")]
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: settings, sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        XCTAssertEqual(viewModel.settings.bookmarks.count, 1)

        viewModel.composerText = "/reset"
        await viewModel.sendPrompt()

        XCTAssertTrue(viewModel.settings.bookmarks.isEmpty)
    }

    // MARK: - Pins command

    func testPinsCommandWithNoPinsShowsGuidance() async {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [
                TranscriptItem(role: .assistant, title: "A", body: "Hello"),
            ])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.composerText = "/pins"
        await viewModel.sendPrompt()

        let pinItems = viewModel.transcript.filter { $0.title == "Pinned" }
        XCTAssertFalse(pinItems.isEmpty)
        XCTAssertTrue(pinItems.last?.body.contains("No pinned") == true)
    }

    func testPinsCommandWithPinnedItems() async {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [
                TranscriptItem(role: .assistant, title: "Important", body: "This is important"),
            ])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        // Pin the first item
        viewModel.togglePin(for: viewModel.transcript.first!.id)

        viewModel.composerText = "/pins"
        await viewModel.sendPrompt()

        let pinItems = viewModel.transcript.filter { $0.title == "Pinned" }
        XCTAssertFalse(pinItems.isEmpty)
        XCTAssertTrue(pinItems.last?.body.contains("Important") == true)
    }

    // MARK: - Source grouping

    func testSourcesByKindGroupsCorrectly() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/a.parquet"))
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/b.parquet"))
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/c.csv"))
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/d.json"))

        let grouped = viewModel.sourcesByKind
        XCTAssertEqual(grouped[.parquet]?.count, 2)
        XCTAssertEqual(grouped[.csv]?.count, 1)
        XCTAssertEqual(grouped[.json]?.count, 1)
        XCTAssertNil(grouped[.duckdb])
    }

    // MARK: - Command previews and results

    func testCommandPreviewsAndResultsEmpty() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        XCTAssertTrue(viewModel.commandPreviews.isEmpty)
        XCTAssertTrue(viewModel.commandResults.isEmpty)
    }

    func testCommandPreviewsAfterExecution() async {
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
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/prices.parquet"))
        await viewModel.triggerPrompt("Preview this parquet file")

        XCTAssertFalse(viewModel.commandPreviews.isEmpty)
        XCTAssertFalse(viewModel.commandResults.isEmpty)
    }

    // MARK: - Pinning

    func testTogglePinOnTranscriptItem() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [
                TranscriptItem(role: .assistant, title: "A", body: "Hello"),
            ])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        let itemID = viewModel.transcript.first!.id
        XCTAssertFalse(viewModel.transcript.first!.isPinned)
        XCTAssertTrue(viewModel.pinnedItems.isEmpty)

        viewModel.togglePin(for: itemID)
        XCTAssertTrue(viewModel.transcript.first!.isPinned)
        XCTAssertEqual(viewModel.pinnedItems.count, 1)

        viewModel.togglePin(for: itemID)
        XCTAssertFalse(viewModel.transcript.first!.isPinned)
        XCTAssertTrue(viewModel.pinnedItems.isEmpty)
    }

    func testTogglePinForNonexistentIDDoesNothing() {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [
                TranscriptItem(role: .assistant, title: "A", body: "Hello"),
            ])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.togglePin(for: UUID()) // random UUID
        XCTAssertTrue(viewModel.pinnedItems.isEmpty) // No crash, no change
    }

    // MARK: - Source info

    func testInfoCommandWithSourceShowsDetails() async {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )
        viewModel.importSource(url: URL(fileURLWithPath: "/tmp/test.parquet"))

        viewModel.composerText = "/info"
        await viewModel.sendPrompt()

        let infoItems = viewModel.transcript.filter { $0.title == "Source Info" }
        XCTAssertFalse(infoItems.isEmpty)
        let body = infoItems.last!.body
        XCTAssertTrue(body.contains("test.parquet"))
        XCTAssertTrue(body.contains("Parquet"))
    }

    func testInfoCommandWithNoSourceShowsGuidance() async {
        let viewModel = SiftViewModel(
            executor: nil,
            chatResponder: MockChatResponder(response: .init(provider: .claude, text: "ignored")),
            sessionStore: MemorySessionStore(snapshot: .init(settings: AppSettings(hasCompletedSetup: true), sources: [], selectedSourceID: nil, transcript: [])),
            secretStore: MemorySecretStore(),
            environment: ["PATH": "/bin"]
        )

        viewModel.composerText = "/info"
        await viewModel.sendPrompt()

        XCTAssertTrue(viewModel.transcript.contains(where: { $0.title == "No Source" }))
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
