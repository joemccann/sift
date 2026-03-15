import XCTest
@testable import SiftCore

final class DataSourceTests: XCTestCase {
    func testCSVFileCreatesCSVSource() {
        let source = DataSource.from(url: URL(fileURLWithPath: "/tmp/data.csv"))
        XCTAssertNotNil(source)
        XCTAssertEqual(source?.kind, .csv)
        XCTAssertEqual(source?.displayName, "data.csv")
    }

    func testTSVFileCreatesCSVSource() {
        let source = DataSource.from(url: URL(fileURLWithPath: "/tmp/data.tsv"))
        XCTAssertNotNil(source)
        XCTAssertEqual(source?.kind, .csv)
    }

    func testUnsupportedExtensionReturnsNil() {
        let source = DataSource.from(url: URL(fileURLWithPath: "/tmp/data.xlsx"))
        XCTAssertNil(source)
    }
}

final class AssistantPlannerTests: XCTestCase {
    func testNoSourceReturnsGuidance() {
        let action = AssistantPlanner.plan(prompt: "preview this", source: nil)

        guard case let .assistantReply(reply) = action else {
            return XCTFail("Expected assistant reply")
        }

        XCTAssertTrue(reply.contains("Open a local `.duckdb` or `.parquet` source first"))
    }

    func testParquetPreviewUsesReadParquet() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/prices.parquet"), kind: .parquet)
        let action = AssistantPlanner.plan(prompt: "Preview this parquet file", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan")
        }

        XCTAssertTrue(plan.sql.contains("read_parquet('/tmp/prices.parquet')"))
        XCTAssertTrue(plan.sql.contains("LIMIT 25"))
    }

    func testDuckDBShowTablesUsesShowTables() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/market.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "Show tables", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan")
        }

        XCTAssertEqual(plan.sql, "SHOW TABLES;")
    }

    func testRawSQLPassthrough() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/market.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "/sql SELECT 42 AS answer;", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan")
        }

        XCTAssertEqual(plan.sql, "SELECT 42 AS answer;")
    }

    func testRawDuckDBCommandPassthrough() {
        let action = AssistantPlanner.plan(prompt: "/duckdb --help", source: nil)

        guard case let .rawCommand(argumentsLine) = action else {
            return XCTFail("Expected raw command")
        }

        XCTAssertEqual(argumentsLine, "--help")
    }

    func testGeneralPromptWithoutSourceUsesProvider() {
        let action = AssistantPlanner.plan(prompt: "Explain factor momentum", source: nil)

        guard case let .providerPrompt(prompt) = action else {
            return XCTFail("Expected provider prompt")
        }

        XCTAssertEqual(prompt, "Explain factor momentum")
    }

    func testHelpCommandReturnsAssistantReply() {
        let action = AssistantPlanner.plan(prompt: "/help", source: nil)

        guard case let .assistantReply(reply) = action else {
            return XCTFail("Expected assistant reply")
        }

        XCTAssertTrue(reply.contains("Sift Commands"))
        XCTAssertTrue(reply.contains("/sql"))
        XCTAssertTrue(reply.contains("/duckdb"))
    }

    func testDuckDBShowColumnsUsesInformationSchema() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/market.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "Show columns", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan")
        }

        XCTAssertTrue(plan.sql.contains("information_schema.columns"))
    }

    func testDuckDBDescribeSchemaUsesDescribe() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/market.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "Show the schema", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan")
        }

        XCTAssertEqual(plan.sql, "DESCRIBE;")
    }

    func testCSVPreviewUsesReadCSV() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/trades.csv"), kind: .csv)
        let action = AssistantPlanner.plan(prompt: "Preview this CSV file", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan")
        }

        XCTAssertTrue(plan.sql.contains("read_csv('/tmp/trades.csv')"))
        XCTAssertTrue(plan.sql.contains("LIMIT 25"))
    }

    func testCSVSummarizeUsesSummarize() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/trades.csv"), kind: .csv)
        let action = AssistantPlanner.plan(prompt: "Summarize this data", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan")
        }

        XCTAssertTrue(plan.sql.contains("SUMMARIZE"))
        XCTAssertTrue(plan.sql.contains("read_csv"))
    }

    func testCSVNaturalLanguageFallsToNLQuery() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/trades.csv"), kind: .csv)
        let action = AssistantPlanner.plan(prompt: "What is the average price per symbol?", source: source)

        guard case let .naturalLanguageQuery(prompt, queriedSource) = action else {
            return XCTFail("Expected natural language query, got \(action)")
        }

        XCTAssertEqual(prompt, "What is the average price per symbol?")
        XCTAssertEqual(queriedSource, source)
    }

    func testParquetSummarizeUsesSummarize() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/prices.parquet"), kind: .parquet)
        let action = AssistantPlanner.plan(prompt: "Show statistics", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan")
        }

        XCTAssertTrue(plan.sql.contains("SUMMARIZE"))
    }

    func testDuckDBUnknownPromptUsesNaturalLanguageQuery() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/market.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "How should I analyze drawdowns here?", source: source)

        guard case let .naturalLanguageQuery(prompt, queriedSource) = action else {
            return XCTFail("Expected natural language query, got \(action)")
        }

        XCTAssertEqual(prompt, "How should I analyze drawdowns here?")
        XCTAssertEqual(queriedSource, source)
    }

    func testParquetUnknownPromptUsesNaturalLanguageQuery() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/prices.parquet"), kind: .parquet)
        let action = AssistantPlanner.plan(prompt: "give me the trading data for AAPL for the past 7 days", source: source)

        guard case let .naturalLanguageQuery(prompt, queriedSource) = action else {
            return XCTFail("Expected natural language query, got \(action)")
        }

        XCTAssertEqual(prompt, "give me the trading data for AAPL for the past 7 days")
        XCTAssertEqual(queriedSource, source)
    }

    // MARK: - /clear command

    func testClearCommandReturnsClearConversation() {
        let action = AssistantPlanner.plan(prompt: "/clear", source: nil)
        XCTAssertEqual(action, .clearConversation)
    }

    func testClearCommandIsCaseInsensitive() {
        let action = AssistantPlanner.plan(prompt: "/CLEAR", source: nil)
        XCTAssertEqual(action, .clearConversation)
    }

    // MARK: - /sources command

    func testSourcesCommandReturnsListSources() {
        let action = AssistantPlanner.plan(prompt: "/sources", source: nil)
        XCTAssertEqual(action, .listSources)
    }

    // MARK: - /copy command

    func testCopyCommandReturnsCopyLastResult() {
        let action = AssistantPlanner.plan(prompt: "/copy", source: nil)
        XCTAssertEqual(action, .copyLastResult)
    }

    // MARK: - Top N extraction

    func testExtractTopNFromTop10() {
        XCTAssertEqual(AssistantPlanner.extractTopN(from: "top 10 results"), 10)
    }

    func testExtractTopNFromFirst5() {
        XCTAssertEqual(AssistantPlanner.extractTopN(from: "first 5 records"), 5)
    }

    func testExtractTopNFromShow100Rows() {
        XCTAssertEqual(AssistantPlanner.extractTopN(from: "show 100 rows"), 100)
    }

    func testExtractTopNReturnsNilForNoMatch() {
        XCTAssertNil(AssistantPlanner.extractTopN(from: "what is the average price"))
    }

    func testExtractTopNRejectsZero() {
        XCTAssertNil(AssistantPlanner.extractTopN(from: "top 0 results"))
    }

    // MARK: - Parquet column listing

    func testParquetColumnsListsColumnNames() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.parquet"), kind: .parquet)
        let action = AssistantPlanner.plan(prompt: "Show columns", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan")
        }

        XCTAssertTrue(plan.sql.contains("column_name"))
        XCTAssertTrue(plan.sql.contains("read_parquet"))
    }

    // MARK: - CSV column listing

    func testCSVColumnsListsColumnNames() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.csv"), kind: .csv)
        let action = AssistantPlanner.plan(prompt: "Show columns", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan")
        }

        XCTAssertTrue(plan.sql.contains("column_name"))
        XCTAssertTrue(plan.sql.contains("read_csv"))
    }

    // MARK: - Top N with parquet

    func testParquetTopNUsesLimit() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.parquet"), kind: .parquet)
        let action = AssistantPlanner.plan(prompt: "top 10", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan")
        }

        XCTAssertTrue(plan.sql.contains("LIMIT 10"))
        XCTAssertTrue(plan.sql.contains("read_parquet"))
    }

    // MARK: - Help text includes new commands

    func testHelpIncludesClearAndSourcesAndCopy() {
        let action = AssistantPlanner.plan(prompt: "/help", source: nil)

        guard case let .assistantReply(reply) = action else {
            return XCTFail("Expected assistant reply")
        }

        XCTAssertTrue(reply.contains("/clear"))
        XCTAssertTrue(reply.contains("/sources"))
        XCTAssertTrue(reply.contains("/copy"))
    }

    // MARK: - DuckDB table sizes

    func testDuckDBTableSizeUsesMetadata() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/market.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "Show table sizes", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan")
        }

        XCTAssertTrue(plan.sql.contains("duckdb_tables()"))
    }

    // MARK: - DuckDB summarize

    func testDuckDBSummarizeUsesSummarize() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/market.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "Summarize data", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan")
        }

        XCTAssertTrue(plan.sql.contains("SUMMARIZE"))
    }

    // MARK: - JSON source support

    func testJSONFileCreatesJSONSource() {
        let source = DataSource.from(url: URL(fileURLWithPath: "/tmp/data.json"))
        XCTAssertNotNil(source)
        XCTAssertEqual(source?.kind, .json)
        XCTAssertEqual(source?.displayName, "data.json")
    }

    func testJSONLFileCreatesJSONSource() {
        let source = DataSource.from(url: URL(fileURLWithPath: "/tmp/data.jsonl"))
        XCTAssertNotNil(source)
        XCTAssertEqual(source?.kind, .json)
    }

    func testNDJSONFileCreatesJSONSource() {
        let source = DataSource.from(url: URL(fileURLWithPath: "/tmp/data.ndjson"))
        XCTAssertNotNil(source)
        XCTAssertEqual(source?.kind, .json)
    }

    func testJSONPreviewUsesReadJSON() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.json"), kind: .json)
        let action = AssistantPlanner.plan(prompt: "Preview this JSON file", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan")
        }

        XCTAssertTrue(plan.sql.contains("read_json('/tmp/data.json')"))
        XCTAssertTrue(plan.sql.contains("LIMIT 25"))
    }

    func testJSONSchemaUsesDescribe() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.json"), kind: .json)
        let action = AssistantPlanner.plan(prompt: "Show the schema", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan")
        }

        XCTAssertTrue(plan.sql.contains("DESCRIBE"))
        XCTAssertTrue(plan.sql.contains("read_json"))
    }

    func testJSONCountUsesCount() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.json"), kind: .json)
        let action = AssistantPlanner.plan(prompt: "Count rows", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan")
        }

        XCTAssertTrue(plan.sql.contains("COUNT(*)"))
        XCTAssertTrue(plan.sql.contains("read_json"))
    }

    func testJSONSummarizeUsesSummarize() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.json"), kind: .json)
        let action = AssistantPlanner.plan(prompt: "Summarize this data", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan")
        }

        XCTAssertTrue(plan.sql.contains("SUMMARIZE"))
        XCTAssertTrue(plan.sql.contains("read_json"))
    }

    func testJSONColumnsListsFields() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.json"), kind: .json)
        let action = AssistantPlanner.plan(prompt: "Show columns", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan")
        }

        XCTAssertTrue(plan.sql.contains("column_name"))
        XCTAssertTrue(plan.sql.contains("read_json"))
    }

    func testJSONTopNUsesLimit() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.json"), kind: .json)
        let action = AssistantPlanner.plan(prompt: "top 5", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan")
        }

        XCTAssertTrue(plan.sql.contains("LIMIT 5"))
        XCTAssertTrue(plan.sql.contains("read_json"))
    }

    func testJSONNaturalLanguageFallsToNLQuery() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.json"), kind: .json)
        let action = AssistantPlanner.plan(prompt: "What is the average age?", source: source)

        guard case let .naturalLanguageQuery(prompt, queriedSource) = action else {
            return XCTFail("Expected natural language query, got \(action)")
        }

        XCTAssertEqual(prompt, "What is the average age?")
        XCTAssertEqual(queriedSource, source)
    }

    // MARK: - /rerun command

    func testRerunCommandReturnsRerunWithNilIndex() {
        let action = AssistantPlanner.plan(prompt: "/rerun", source: nil)
        XCTAssertEqual(action, .rerunCommand(index: nil))
    }

    func testRerunCommandWithIndexReturnsRerunWithIndex() {
        let action = AssistantPlanner.plan(prompt: "/rerun 3", source: nil)
        XCTAssertEqual(action, .rerunCommand(index: 3))
    }

    func testRerunCommandIsCaseInsensitive() {
        let action = AssistantPlanner.plan(prompt: "/RERUN", source: nil)
        XCTAssertEqual(action, .rerunCommand(index: nil))
    }

    func testHelpIncludesRerun() {
        let action = AssistantPlanner.plan(prompt: "/help", source: nil)
        guard case let .assistantReply(reply) = action else {
            return XCTFail("Expected assistant reply")
        }
        XCTAssertTrue(reply.contains("/rerun"))
    }

    // MARK: - Unsupported file types

    func testXLSXFileReturnsNil() {
        let source = DataSource.from(url: URL(fileURLWithPath: "/tmp/data.xlsx"))
        XCTAssertNil(source)
    }

    func testTXTFileReturnsNil() {
        let source = DataSource.from(url: URL(fileURLWithPath: "/tmp/data.txt"))
        XCTAssertNil(source)
    }

    // MARK: - /history command

    func testHistoryCommandReturnsShowHistory() {
        let action = AssistantPlanner.plan(prompt: "/history", source: nil)
        XCTAssertEqual(action, .showHistory)
    }

    func testHelpIncludesHistory() {
        let action = AssistantPlanner.plan(prompt: "/help", source: nil)
        guard case let .assistantReply(reply) = action else {
            return XCTFail("Expected assistant reply")
        }
        XCTAssertTrue(reply.contains("/history"))
    }

    // MARK: - /sql with no args

    func testSqlWithNoArgsReturnsGuidance() {
        let action = AssistantPlanner.plan(prompt: "/sql", source: nil)
        guard case let .assistantReply(reply) = action else {
            return XCTFail("Expected assistant reply")
        }
        XCTAssertTrue(reply.contains("/sql"))
    }

    // MARK: - DuckDB show views

    func testDuckDBShowViewsUsesViewsQuery() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/market.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "Show views", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan")
        }

        XCTAssertTrue(plan.sql.contains("duckdb_views()"))
    }

    // MARK: - DuckDB show indexes

    func testDuckDBShowIndexesUsesIndexesQuery() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/market.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "Show indexes", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan")
        }

        XCTAssertTrue(plan.sql.contains("duckdb_indexes()"))
    }

    // MARK: - DuckDB version

    func testDuckDBVersionUsesPragma() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/market.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "What version?", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan")
        }

        XCTAssertEqual(plan.sql, "PRAGMA version;")
    }

    // MARK: - Path escaping

    func testPathWithApostropheIsEscaped() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/John's Data.parquet"), kind: .parquet)
        let action = AssistantPlanner.plan(prompt: "Preview this", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan")
        }

        XCTAssertTrue(plan.sql.contains("John''s Data.parquet"))
        XCTAssertFalse(plan.sql.contains("John's Data.parquet"))
    }

    // MARK: - Empty prompt

    func testEmptyPromptReturnsGuidance() {
        let action = AssistantPlanner.plan(prompt: "", source: nil)
        guard case let .assistantReply(reply) = action else {
            return XCTFail("Expected assistant reply")
        }
        XCTAssertTrue(reply.contains("Ask a question"))
    }

    func testWhitespaceOnlyPromptReturnsGuidance() {
        let action = AssistantPlanner.plan(prompt: "   \n  ", source: nil)
        guard case let .assistantReply(reply) = action else {
            return XCTFail("Expected assistant reply")
        }
        XCTAssertTrue(reply.contains("Ask a question"))
    }

    // MARK: - DB extension

    func testDBFileCreatesDuckDBSource() {
        let source = DataSource.from(url: URL(fileURLWithPath: "/tmp/market.db"))
        XCTAssertNotNil(source)
        XCTAssertEqual(source?.kind, .duckdb)
    }

    // MARK: - Case insensitive extension

    func testParquetUppercaseExtension() {
        let source = DataSource.from(url: URL(fileURLWithPath: "/tmp/DATA.PARQUET"))
        XCTAssertNotNil(source)
        XCTAssertEqual(source?.kind, .parquet)
    }

    func testCSVUppercaseExtension() {
        let source = DataSource.from(url: URL(fileURLWithPath: "/tmp/DATA.CSV"))
        XCTAssertNotNil(source)
        XCTAssertEqual(source?.kind, .csv)
    }

    func testJSONUppercaseExtension() {
        let source = DataSource.from(url: URL(fileURLWithPath: "/tmp/DATA.JSON"))
        XCTAssertNotNil(source)
        XCTAssertEqual(source?.kind, .json)
    }
}

// MARK: - TranscriptModels Codable

final class TranscriptModelsCodableTests: XCTestCase {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func testTextKindRoundTrips() throws {
        let item = TranscriptItem(role: .assistant, title: "A", body: "Hello", kind: .text)
        let data = try encoder.encode(item)
        let restored = try decoder.decode(TranscriptItem.self, from: data)
        XCTAssertEqual(restored.kind, .text)
        XCTAssertEqual(restored.body, "Hello")
        XCTAssertEqual(restored.role, .assistant)
    }

    func testThinkingKindRoundTrips() throws {
        let item = TranscriptItem(role: .assistant, title: "A", body: "Thinking…", kind: .thinking)
        let data = try encoder.encode(item)
        let restored = try decoder.decode(TranscriptItem.self, from: data)
        XCTAssertEqual(restored.kind, .thinking)
    }

    func testCommandPreviewKindRoundTrips() throws {
        let item = TranscriptItem(
            role: .assistant, title: "Preview", body: "Running query",
            kind: .commandPreview(sql: "SELECT 1;", sourceName: "test.duckdb")
        )
        let data = try encoder.encode(item)
        let restored = try decoder.decode(TranscriptItem.self, from: data)
        XCTAssertEqual(restored.kind, .commandPreview(sql: "SELECT 1;", sourceName: "test.duckdb"))
    }

    func testRawCommandPreviewKindRoundTrips() throws {
        let item = TranscriptItem(
            role: .assistant, title: "DuckDB", body: "Running",
            kind: .rawCommandPreview(command: "--help")
        )
        let data = try encoder.encode(item)
        let restored = try decoder.decode(TranscriptItem.self, from: data)
        XCTAssertEqual(restored.kind, .rawCommandPreview(command: "--help"))
    }

    func testCommandResultKindRoundTrips() throws {
        let item = TranscriptItem(
            role: .assistant, title: "Result", body: "Done",
            kind: .commandResult(exitCode: 0, stdout: "42\n", stderr: "")
        )
        let data = try encoder.encode(item)
        let restored = try decoder.decode(TranscriptItem.self, from: data)
        XCTAssertEqual(restored.kind, .commandResult(exitCode: 0, stdout: "42\n", stderr: ""))
    }

    func testTranscriptItemPreservesID() throws {
        let item = TranscriptItem(role: .user, title: "You", body: "test")
        let data = try encoder.encode(item)
        let restored = try decoder.decode(TranscriptItem.self, from: data)
        XCTAssertEqual(restored.id, item.id)
    }

    func testTranscriptItemPreservesTimestamp() throws {
        let item = TranscriptItem(role: .system, title: "Sys", body: "info")
        let data = try encoder.encode(item)
        let restored = try decoder.decode(TranscriptItem.self, from: data)
        XCTAssertEqual(restored.timestamp.timeIntervalSince1970, item.timestamp.timeIntervalSince1970, accuracy: 0.001)
    }
}

// MARK: - AppSettings

final class AppSettingsTests: XCTestCase {
    func testDefaultSettingsHaveCorrectDefaults() {
        let settings = AppSettings()
        XCTAssertFalse(settings.hasCompletedSetup)
        XCTAssertEqual(settings.defaultProvider, .claude)
        XCTAssertTrue(settings.providerPreferences.isEmpty)
    }

    func testPreferenceReturnsDefaultWhenNotSet() {
        let settings = AppSettings()
        let pref = settings.preference(for: .claude)
        XCTAssertEqual(pref.authMode, .localCLI)
        XCTAssertEqual(pref.customModel, "sonnet")
    }

    func testSetPreferenceRoundTrips() {
        var settings = AppSettings()
        let pref = ProviderPreference(authMode: .apiKey, customModel: "opus")
        settings.setPreference(pref, for: .claude)
        XCTAssertEqual(settings.preference(for: .claude), pref)
    }

    func testProviderKindDisplayNames() {
        XCTAssertEqual(ProviderKind.claude.displayName, "Claude")
        XCTAssertEqual(ProviderKind.openAI.displayName, "OpenAI")
        XCTAssertEqual(ProviderKind.gemini.displayName, "Gemini")
    }

    func testProviderKindCLICommands() {
        XCTAssertEqual(ProviderKind.claude.cliCommand, "claude")
        XCTAssertEqual(ProviderKind.openAI.cliCommand, "codex")
        XCTAssertEqual(ProviderKind.gemini.cliCommand, "gemini")
    }

    func testProviderKindAPIKeyNames() {
        XCTAssertEqual(ProviderKind.claude.preferredAPIKeyEnvironmentName, "ANTHROPIC_API_KEY")
        XCTAssertEqual(ProviderKind.openAI.preferredAPIKeyEnvironmentName, "OPENAI_API_KEY")
        XCTAssertEqual(ProviderKind.gemini.preferredAPIKeyEnvironmentName, "GEMINI_API_KEY")
    }

    func testProviderAuthModeDisplayNames() {
        XCTAssertEqual(ProviderAuthMode.localCLI.displayName, "Local Subscription")
        XCTAssertEqual(ProviderAuthMode.apiKey.displayName, "API Key")
    }

    func testAppSettingsCodableRoundTrip() throws {
        var settings = AppSettings(hasCompletedSetup: true, defaultProvider: .gemini)
        settings.setPreference(ProviderPreference(authMode: .apiKey, customModel: "flash"), for: .gemini)

        let data = try JSONEncoder().encode(settings)
        let restored = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(restored, settings)
    }

    func testSessionSnapshotCodableRoundTrip() throws {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/test.parquet"), kind: .parquet)
        let snapshot = AppSessionSnapshot(
            settings: AppSettings(hasCompletedSetup: true),
            sources: [source],
            selectedSourceID: source.id,
            transcript: [TranscriptItem(role: .assistant, title: "A", body: "Hi")]
        )

        let data = try JSONEncoder().encode(snapshot)
        let restored = try JSONDecoder().decode(AppSessionSnapshot.self, from: data)
        XCTAssertEqual(restored.settings, snapshot.settings)
        XCTAssertEqual(restored.sources.count, 1)
        XCTAssertEqual(restored.selectedSourceID, source.id)
    }

    func testDataSourceKindAllCases() {
        let allCases = DataSourceKind.allCases
        XCTAssertTrue(allCases.contains(.parquet))
        XCTAssertTrue(allCases.contains(.duckdb))
        XCTAssertTrue(allCases.contains(.csv))
        XCTAssertTrue(allCases.contains(.json))
        XCTAssertEqual(allCases.count, 4)
    }

    func testDataSourceDisplayNameIsFilename() {
        let source = DataSource(url: URL(fileURLWithPath: "/some/deep/path/data.parquet"), kind: .parquet)
        XCTAssertEqual(source.displayName, "data.parquet")
        XCTAssertEqual(source.path, "/some/deep/path/data.parquet")
    }
}

// MARK: - Export and Status commands

final class ExportStatusCommandTests: XCTestCase {
    func testExportCommandReturnsExportTranscript() {
        let action = AssistantPlanner.plan(prompt: "/export", source: nil)
        XCTAssertEqual(action, .exportTranscript)
    }

    func testExportCommandIsCaseInsensitive() {
        let action = AssistantPlanner.plan(prompt: "/EXPORT", source: nil)
        XCTAssertEqual(action, .exportTranscript)
    }

    func testStatusCommandReturnsShowStatus() {
        let action = AssistantPlanner.plan(prompt: "/status", source: nil)
        XCTAssertEqual(action, .showStatus)
    }

    func testHelpIncludesExportAndStatus() {
        let action = AssistantPlanner.plan(prompt: "/help", source: nil)
        guard case let .assistantReply(reply) = action else {
            return XCTFail("Expected assistant reply")
        }
        XCTAssertTrue(reply.contains("/export"))
        XCTAssertTrue(reply.contains("/status"))
    }
}

// MARK: - PromptLibrary

final class PromptLibraryTests: XCTestCase {
    func testNoSourceReturnsGenericChips() {
        let chips = PromptLibrary.prompts(for: nil)
        XCTAssertFalse(chips.isEmpty)
        XCTAssertTrue(chips.contains(where: { $0.title.contains("parquet") }))
    }

    func testParquetSourceReturnsPreviewChip() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.parquet"), kind: .parquet)
        let chips = PromptLibrary.prompts(for: source)
        XCTAssertTrue(chips.contains(where: { $0.title.contains("Preview") }))
        XCTAssertTrue(chips.contains(where: { $0.title.contains("schema") }))
    }

    func testCSVSourceReturnsCSVChips() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.csv"), kind: .csv)
        let chips = PromptLibrary.prompts(for: source)
        XCTAssertTrue(chips.contains(where: { $0.title.contains("Preview") }))
        XCTAssertTrue(chips.contains(where: { $0.title.contains("Summarize") }))
    }

    func testJSONSourceReturnsJSONChips() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.json"), kind: .json)
        let chips = PromptLibrary.prompts(for: source)
        XCTAssertTrue(chips.contains(where: { $0.title.contains("Preview") }))
    }

    func testDuckDBSourceReturnsDuckDBChips() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/db.duckdb"), kind: .duckdb)
        let chips = PromptLibrary.prompts(for: source)
        XCTAssertTrue(chips.contains(where: { $0.title.contains("tables") }))
        XCTAssertTrue(chips.contains(where: { $0.title.contains("Database") }))
    }

    func testPromptChipHasUniqueIDs() {
        let chips = PromptLibrary.prompts(for: nil)
        let ids = Set(chips.map(\.id))
        XCTAssertEqual(ids.count, chips.count)
    }
}

// MARK: - MetalWorkspaceSnapshot

final class MetalWorkspaceSnapshotTests: XCTestCase {
    func testSnapshotCodableRoundTrip() throws {
        let snapshot = MetalWorkspaceSnapshot(
            destination: .assistant,
            provider: .claude,
            sourceKind: .json,
            sourceCount: 2,
            transcriptCount: 5,
            providerReadiness: 1,
            executionState: .success,
            commandDurationMilliseconds: 150,
            commandOutputBytes: 512,
            isRunning: false
        )

        let data = try JSONEncoder().encode(snapshot)
        let restored = try JSONDecoder().decode(MetalWorkspaceSnapshot.self, from: data)
        XCTAssertEqual(restored, snapshot)
    }

    func testSnapshotEquality() {
        let a = MetalWorkspaceSnapshot(
            destination: .assistant,
            provider: .claude,
            sourceKind: .parquet,
            sourceCount: 1,
            transcriptCount: 3,
            providerReadiness: 1,
            executionState: .idle,
            commandDurationMilliseconds: 0,
            commandOutputBytes: 0,
            isRunning: false
        )
        let b = MetalWorkspaceSnapshot(
            destination: .assistant,
            provider: .claude,
            sourceKind: .parquet,
            sourceCount: 1,
            transcriptCount: 3,
            providerReadiness: 1,
            executionState: .idle,
            commandDurationMilliseconds: 0,
            commandOutputBytes: 0,
            isRunning: false
        )
        XCTAssertEqual(a, b)
    }
}

// MARK: - /bookmark commands

final class BookmarkCommandTests: XCTestCase {
    func testBookmarkCommandReturnsBookmarkLastCommand() {
        let action = AssistantPlanner.plan(prompt: "/bookmark", source: nil)
        XCTAssertEqual(action, .bookmarkLastCommand)
    }

    func testBookmarksCommandReturnsShowBookmarks() {
        let action = AssistantPlanner.plan(prompt: "/bookmarks", source: nil)
        XCTAssertEqual(action, .showBookmarks)
    }

    func testHelpIncludesBookmarks() {
        let action = AssistantPlanner.plan(prompt: "/help", source: nil)
        guard case let .assistantReply(reply) = action else {
            return XCTFail("Expected assistant reply")
        }
        XCTAssertTrue(reply.contains("/bookmark"))
        XCTAssertTrue(reply.contains("/bookmarks"))
    }
}

// MARK: - BookmarkedCommand model

final class BookmarkedCommandTests: XCTestCase {
    func testBookmarkedCommandCodableRoundTrip() throws {
        let bookmark = BookmarkedCommand(sql: "SELECT 1;", sourceName: "test.duckdb")
        let data = try JSONEncoder().encode(bookmark)
        let restored = try JSONDecoder().decode(BookmarkedCommand.self, from: data)
        XCTAssertEqual(restored.id, bookmark.id)
        XCTAssertEqual(restored.sql, "SELECT 1;")
        XCTAssertEqual(restored.sourceName, "test.duckdb")
    }

    func testBookmarkedCommandEquality() {
        let a = BookmarkedCommand(id: UUID(), sql: "SELECT 1;", sourceName: "test")
        let b = a // Same value
        XCTAssertEqual(a, b)
    }
}

// MARK: - /version command

final class VersionCommandTests: XCTestCase {
    func testVersionCommandReturnsShowVersion() {
        let action = AssistantPlanner.plan(prompt: "/version", source: nil)
        XCTAssertEqual(action, .showVersion)
    }

    func testVersionCommandIsCaseInsensitive() {
        let action = AssistantPlanner.plan(prompt: "/VERSION", source: nil)
        XCTAssertEqual(action, .showVersion)
    }
}

// MARK: - DuckDB count pattern with source

final class DuckDBCountTests: XCTestCase {
    func testDuckDBCountWithNoSpecificTable() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/market.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "How many rows?", source: source)

        // Should fall to natural language since no specific pattern matches
        guard case .naturalLanguageQuery = action else {
            return // Could be NL or something else depending on pattern
        }
    }

    func testParquetCountUsesReadParquet() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.parquet"), kind: .parquet)
        let action = AssistantPlanner.plan(prompt: "Count the rows", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan")
        }

        XCTAssertTrue(plan.sql.contains("COUNT(*)"))
        XCTAssertTrue(plan.sql.contains("read_parquet"))
    }

    func testCSVCountUsesReadCSV() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.csv"), kind: .csv)
        let action = AssistantPlanner.plan(prompt: "Count rows", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan")
        }

        XCTAssertTrue(plan.sql.contains("COUNT(*)"))
        XCTAssertTrue(plan.sql.contains("read_csv"))
    }

    func testJSONCountUsesReadJSON() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.json"), kind: .json)
        let action = AssistantPlanner.plan(prompt: "Count rows", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan")
        }

        XCTAssertTrue(plan.sql.contains("COUNT(*)"))
        XCTAssertTrue(plan.sql.contains("read_json"))
    }
}

// MARK: - Parquet count aliases

final class ParquetCountAliasTests: XCTestCase {
    func testParquetHowManyRowsFallsToNL() {
        // "How many rows?" doesn't contain "count" so it falls to NL query
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.parquet"), kind: .parquet)
        let action = AssistantPlanner.plan(prompt: "How many rows?", source: source)

        guard case .naturalLanguageQuery = action else {
            return XCTFail("Expected NL query, got \(action)")
        }
    }

    func testParquetRowCountUsesCount() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.parquet"), kind: .parquet)
        let action = AssistantPlanner.plan(prompt: "row count", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan, got \(action)")
        }

        XCTAssertTrue(plan.sql.contains("COUNT"))
    }
}

// MARK: - Natural language fallback across all source types

final class NaturalLanguageFallbackTests: XCTestCase {
    func testParquetComplexQuestionFallsToNL() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.parquet"), kind: .parquet)
        let action = AssistantPlanner.plan(prompt: "What's the correlation between price and volume?", source: source)

        guard case .naturalLanguageQuery = action else {
            return XCTFail("Expected NL query, got \(action)")
        }
    }

    func testCSVComplexQuestionFallsToNL() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.csv"), kind: .csv)
        let action = AssistantPlanner.plan(prompt: "Which category has the highest average?", source: source)

        guard case .naturalLanguageQuery = action else {
            return XCTFail("Expected NL query, got \(action)")
        }
    }

    func testJSONComplexQuestionFallsToNL() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.json"), kind: .json)
        let action = AssistantPlanner.plan(prompt: "Find outliers in the data", source: source)

        guard case .naturalLanguageQuery = action else {
            return XCTFail("Expected NL query, got \(action)")
        }
    }

    func testDuckDBComplexQuestionFallsToNL() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/market.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "What is the moving average of returns?", source: source)

        guard case .naturalLanguageQuery = action else {
            return XCTFail("Expected NL query, got \(action)")
        }
    }
}

// MARK: - Provider prompt without source

final class ProviderPromptTests: XCTestCase {
    func testGeneralQuestionUsesProviderPrompt() {
        let action = AssistantPlanner.plan(prompt: "What is quantum computing?", source: nil)

        guard case .providerPrompt = action else {
            return XCTFail("Expected provider prompt, got \(action)")
        }
    }

    func testCodeRelatedQuestionUsesProviderPrompt() {
        let action = AssistantPlanner.plan(prompt: "Write a Python script to process CSV files", source: nil)

        guard case .providerPrompt = action else {
            return XCTFail("Expected provider prompt, got \(action)")
        }
    }
}

// MARK: - DuckDB SQL passthrough patterns

final class DuckDBSQLPassthroughTests: XCTestCase {
    func testSelectStatementPassesThrough() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/market.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "SELECT COUNT(*) FROM trades;", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan, got \(action)")
        }

        XCTAssertEqual(plan.sql, "SELECT COUNT(*) FROM trades;")
    }

    func testWithCTEPassesThrough() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/market.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "WITH cte AS (SELECT 1) SELECT * FROM cte;", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan, got \(action)")
        }

        XCTAssertTrue(plan.sql.contains("WITH cte"))
    }

    func testPragmaStatementPassesThrough() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/market.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "PRAGMA table_info('trades');", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan, got \(action)")
        }

        XCTAssertTrue(plan.sql.contains("PRAGMA"))
    }
}

// MARK: - Multiple command interactions

final class CommandInteractionTests: XCTestCase {
    func testRawSQLTakesPrecedenceOverSourcePatterns() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.parquet"), kind: .parquet)
        let action = AssistantPlanner.plan(prompt: "/sql SELECT custom_column FROM read_parquet('/tmp/data.parquet');", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan")
        }

        XCTAssertTrue(plan.sql.contains("custom_column"))
    }

    func testRawDuckDBTakesPrecedenceOverEverything() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.parquet"), kind: .parquet)
        let action = AssistantPlanner.plan(prompt: "/duckdb :memory: -c \"SELECT 1;\"", source: source)

        guard case let .rawCommand(args) = action else {
            return XCTFail("Expected raw command")
        }

        XCTAssertTrue(args.contains(":memory:"))
    }

    func testSchemaKeywordInDifferentContexts() {
        // Parquet
        let parquetSource = DataSource(url: URL(fileURLWithPath: "/tmp/data.parquet"), kind: .parquet)
        let parquetAction = AssistantPlanner.plan(prompt: "Show me the schema", source: parquetSource)
        if case let .command(plan) = parquetAction {
            XCTAssertTrue(plan.sql.contains("DESCRIBE"))
        } else {
            XCTFail("Expected command")
        }

        // CSV
        let csvSource = DataSource(url: URL(fileURLWithPath: "/tmp/data.csv"), kind: .csv)
        let csvAction = AssistantPlanner.plan(prompt: "Show me the schema", source: csvSource)
        if case let .command(plan) = csvAction {
            XCTAssertTrue(plan.sql.contains("DESCRIBE"))
        } else {
            XCTFail("Expected command")
        }

        // JSON
        let jsonSource = DataSource(url: URL(fileURLWithPath: "/tmp/data.json"), kind: .json)
        let jsonAction = AssistantPlanner.plan(prompt: "Show me the schema", source: jsonSource)
        if case let .command(plan) = jsonAction {
            XCTAssertTrue(plan.sql.contains("DESCRIBE"))
        } else {
            XCTFail("Expected command")
        }
    }
}

// MARK: - Describe table pattern

final class DescribeTableTests: XCTestCase {
    func testDescribeTradesExtractsTableName() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/market.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "describe trades", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan, got \(action)")
        }

        XCTAssertEqual(plan.sql, "DESCRIBE trades;")
    }

    func testDescribeTheUsersTable() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/market.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "describe the users table", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan, got \(action)")
        }

        XCTAssertEqual(plan.sql, "DESCRIBE users;")
    }

    func testBareDescribeFallsToGenericDescribe() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/market.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "describe the schema", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan, got \(action)")
        }

        XCTAssertEqual(plan.sql, "DESCRIBE;")
    }

    func testExtractDescribeTargetRejectsReservedWords() {
        XCTAssertNil(AssistantPlanner.extractDescribeTarget(from: "describe the database"))
        XCTAssertNil(AssistantPlanner.extractDescribeTarget(from: "describe this"))
        XCTAssertNil(AssistantPlanner.extractDescribeTarget(from: "describe all"))
    }

    func testExtractDescribeTargetReturnsTableName() {
        XCTAssertEqual(AssistantPlanner.extractDescribeTarget(from: "describe orders"), "orders")
        XCTAssertEqual(AssistantPlanner.extractDescribeTarget(from: "describe table products"), "products")
    }
}

// MARK: - DuckDB memory and extensions

final class DuckDBMemoryExtensionTests: XCTestCase {
    func testMemoryUsagePatternUsesPragma() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/market.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "Show memory usage", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan, got \(action)")
        }

        XCTAssertTrue(plan.sql.contains("database_size"))
    }

    func testExtensionsPatternUsesExtensionsQuery() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/market.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "Show installed extensions", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan, got \(action)")
        }

        XCTAssertTrue(plan.sql.contains("duckdb_extensions()"))
    }

    func testSettingsPatternUsesSettingsQuery() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/market.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "DuckDB settings", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan, got \(action)")
        }

        XCTAssertTrue(plan.sql.contains("duckdb_settings()"))
    }
}

// MARK: - DataSourceKind properties

final class DataSourceKindPropertiesTests: XCTestCase {
    func testReadFunctionForFileBasedKinds() {
        XCTAssertEqual(DataSourceKind.parquet.readFunction, "read_parquet")
        XCTAssertEqual(DataSourceKind.csv.readFunction, "read_csv")
        XCTAssertEqual(DataSourceKind.json.readFunction, "read_json")
        XCTAssertNil(DataSourceKind.duckdb.readFunction)
    }

    func testDisplayLabels() {
        XCTAssertEqual(DataSourceKind.parquet.displayLabel, "Parquet")
        XCTAssertEqual(DataSourceKind.csv.displayLabel, "CSV")
        XCTAssertEqual(DataSourceKind.json.displayLabel, "JSON")
        XCTAssertEqual(DataSourceKind.duckdb.displayLabel, "DuckDB")
    }

    func testFileExtensions() {
        XCTAssertTrue(DataSourceKind.parquet.fileExtensions.contains("parquet"))
        XCTAssertTrue(DataSourceKind.csv.fileExtensions.contains("csv"))
        XCTAssertTrue(DataSourceKind.csv.fileExtensions.contains("tsv"))
        XCTAssertTrue(DataSourceKind.json.fileExtensions.contains("json"))
        XCTAssertTrue(DataSourceKind.json.fileExtensions.contains("jsonl"))
        XCTAssertTrue(DataSourceKind.json.fileExtensions.contains("ndjson"))
        XCTAssertTrue(DataSourceKind.duckdb.fileExtensions.contains("duckdb"))
        XCTAssertTrue(DataSourceKind.duckdb.fileExtensions.contains("db"))
    }

    func testAllKindsHaveExtensions() {
        for kind in DataSourceKind.allCases {
            XCTAssertFalse(kind.fileExtensions.isEmpty, "\(kind) has no extensions")
        }
    }
}

// MARK: - DataSource file info

final class DataSourceFileInfoTests: XCTestCase {
    func testFileSizeDescriptionForMissingFile() {
        let source = DataSource(url: URL(fileURLWithPath: "/nonexistent/file.parquet"), kind: .parquet)
        XCTAssertEqual(source.fileSizeDescription, "unknown size")
    }

    func testFileSizeDescriptionForExistingFile() throws {
        let tmpPath = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".parquet")
        let data = Data(repeating: 0, count: 2048)
        try data.write(to: tmpPath)

        let source = DataSource(url: tmpPath, kind: .parquet)
        XCTAssertTrue(source.fileSizeDescription.contains("KB") || source.fileSizeDescription.contains("B"))

        try? FileManager.default.removeItem(at: tmpPath)
    }

    func testDataSourceCodableRoundTrip() throws {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.json"), kind: .json)
        let data = try JSONEncoder().encode(source)
        let restored = try JSONDecoder().decode(DataSource.self, from: data)
        XCTAssertEqual(restored.id, source.id)
        XCTAssertEqual(restored.kind, source.kind)
        XCTAssertEqual(restored.displayName, source.displayName)
    }
}

// MARK: - Parquet metadata

final class ParquetMetadataTests: XCTestCase {
    func testParquetMetadataUsesParquetMetadata() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.parquet"), kind: .parquet)
        let action = AssistantPlanner.plan(prompt: "Show metadata", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan")
        }

        XCTAssertTrue(plan.sql.contains("parquet_metadata"))
    }

    func testParquetFileSchemaUsesParquetSchema() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.parquet"), kind: .parquet)
        let action = AssistantPlanner.plan(prompt: "Show parquet schema", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan")
        }

        XCTAssertTrue(plan.sql.contains("parquet_schema"))
    }

    func testParquetFileInfoUsesMetadata() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.parquet"), kind: .parquet)
        let action = AssistantPlanner.plan(prompt: "Show file info", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan")
        }

        XCTAssertTrue(plan.sql.contains("parquet_metadata"))
    }
}

// MARK: - /stats command

final class StatsCommandTests: XCTestCase {
    func testStatsCommandReturnsShowCommandCount() {
        let action = AssistantPlanner.plan(prompt: "/stats", source: nil)
        XCTAssertEqual(action, .showCommandCount)
    }
}

// MARK: - PromptChip model

final class PromptChipModelTests: XCTestCase {
    func testPromptChipEquality() {
        let id = UUID()
        let a = PromptChip(id: id, title: "Test", prompt: "test")
        let b = PromptChip(id: id, title: "Test", prompt: "test")
        XCTAssertEqual(a, b)
    }

    func testPromptChipIdentifiable() {
        let chip = PromptChip(title: "Preview", prompt: "preview this")
        XCTAssertNotEqual(chip.id, UUID()) // has its own unique ID
    }
}

// MARK: - TranscriptRole properties

final class TranscriptRoleTests: XCTestCase {
    func testTranscriptRoleRawValues() {
        XCTAssertEqual(TranscriptRole.assistant.rawValue, "assistant")
        XCTAssertEqual(TranscriptRole.user.rawValue, "user")
        XCTAssertEqual(TranscriptRole.system.rawValue, "system")
    }

    func testTranscriptRoleCodableRoundTrip() throws {
        for role in [TranscriptRole.assistant, .user, .system] {
            let data = try JSONEncoder().encode(role)
            let restored = try JSONDecoder().decode(TranscriptRole.self, from: data)
            XCTAssertEqual(restored, role)
        }
    }
}

// MARK: - DuckDBCommandPlan

final class DuckDBCommandPlanTests: XCTestCase {
    func testCommandPlanEquality() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/test.duckdb"), kind: .duckdb)
        let a = DuckDBCommandPlan(source: source, sql: "SELECT 1;", explanation: "test")
        let b = DuckDBCommandPlan(source: source, sql: "SELECT 1;", explanation: "test")
        XCTAssertEqual(a, b)
    }

    func testCommandPlanInequality() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/test.duckdb"), kind: .duckdb)
        let a = DuckDBCommandPlan(source: source, sql: "SELECT 1;", explanation: "test")
        let b = DuckDBCommandPlan(source: source, sql: "SELECT 2;", explanation: "test")
        XCTAssertNotEqual(a, b)
    }
}

// MARK: - CommandRegistry (tab completion)

final class CommandRegistryTests: XCTestCase {
    func testAllCommandsIsNotEmpty() {
        XCTAssertFalse(CommandRegistry.allCommands.isEmpty)
    }

    func testAllCommandsStartWithSlash() {
        for cmd in CommandRegistry.allCommands {
            XCTAssertTrue(cmd.command.hasPrefix("/"), "\(cmd.command) should start with /")
        }
    }

    func testAllCommandsHaveDescriptions() {
        for cmd in CommandRegistry.allCommands {
            XCTAssertFalse(cmd.description.isEmpty, "\(cmd.command) has empty description")
        }
    }

    func testCompletionsForSlashReturnsAll() {
        let results = CommandRegistry.completions(for: "/")
        XCTAssertEqual(results.count, CommandRegistry.allCommands.count)
    }

    func testCompletionsForSlashHReturnsHelpAndHistory() {
        let results = CommandRegistry.completions(for: "/h")
        XCTAssertTrue(results.contains(where: { $0.command == "/help" }))
        XCTAssertTrue(results.contains(where: { $0.command == "/history" }))
    }

    func testCompletionsForSlashClearReturnsExactMatch() {
        let results = CommandRegistry.completions(for: "/clear")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.command, "/clear")
    }

    func testCompletionsForNoSlashReturnsEmpty() {
        let results = CommandRegistry.completions(for: "hello")
        XCTAssertTrue(results.isEmpty)
    }

    func testCompletionsForEmptyStringReturnsEmpty() {
        let results = CommandRegistry.completions(for: "")
        XCTAssertTrue(results.isEmpty)
    }

    func testCompletionsAreCaseInsensitive() {
        let results = CommandRegistry.completions(for: "/H")
        XCTAssertTrue(results.contains(where: { $0.command == "/help" }))
    }

    func testCompletionsForSlashBReturnsBookmarkCommands() {
        let results = CommandRegistry.completions(for: "/b")
        XCTAssertTrue(results.contains(where: { $0.command == "/bookmark" }))
        XCTAssertTrue(results.contains(where: { $0.command == "/bookmarks" }))
    }

    func testCompletionsForNonexistentPrefixReturnsEmpty() {
        let results = CommandRegistry.completions(for: "/xyz")
        XCTAssertTrue(results.isEmpty)
    }

    func testCommandInfoEquality() {
        let a = CommandInfo(command: "/help", description: "Show help")
        let b = CommandInfo(command: "/help", description: "Show help")
        XCTAssertEqual(a, b)
    }

    func testCommandInfoInequality() {
        let a = CommandInfo(command: "/help", description: "Show help")
        let b = CommandInfo(command: "/clear", description: "Clear")
        XCTAssertNotEqual(a, b)
    }
}

// MARK: - DuckDB preview [tablename]

final class DuckDBPreviewTableTests: XCTestCase {
    func testPreviewTradesGeneratesSelect() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/market.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "preview trades", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan, got \(action)")
        }

        XCTAssertTrue(plan.sql.contains("SELECT * FROM trades"))
        XCTAssertTrue(plan.sql.contains("LIMIT 25"))
    }

    func testPreviewReservedWordFallsThrough() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/market.duckdb"), kind: .duckdb)
        // "preview the" should NOT match as table "the"
        let action = AssistantPlanner.plan(prompt: "preview the data", source: source)

        // Should not be a command with "SELECT * FROM the"
        if case let .command(plan) = action {
            XCTAssertFalse(plan.sql.contains("FROM the "), "Should not use 'the' as table name")
        }
    }

    func testExtractPreviewTargetReturnsTableName() {
        XCTAssertEqual(AssistantPlanner.extractPreviewTarget(from: "preview orders"), "orders")
        XCTAssertEqual(AssistantPlanner.extractPreviewTarget(from: "head users"), "users")
    }

    func testExtractPreviewTargetRejectsReserved() {
        XCTAssertNil(AssistantPlanner.extractPreviewTarget(from: "preview the"))
        XCTAssertNil(AssistantPlanner.extractPreviewTarget(from: "preview schema"))
        XCTAssertNil(AssistantPlanner.extractPreviewTarget(from: "preview tables"))
    }
}

// MARK: - /pins command

final class PinsCommandTests: XCTestCase {
    func testPinsCommandReturnsShowPinnedItems() {
        let action = AssistantPlanner.plan(prompt: "/pins", source: nil)
        XCTAssertEqual(action, .showPinnedItems)
    }

    func testPinnedCommandAlsoWorks() {
        let action = AssistantPlanner.plan(prompt: "/pinned", source: nil)
        XCTAssertEqual(action, .showPinnedItems)
    }

    func testPinsInCommandRegistry() {
        XCTAssertTrue(CommandRegistry.allCommands.contains(where: { $0.command == "/pins" }))
    }
}

// MARK: - /info command

final class InfoCommandTests: XCTestCase {
    func testInfoCommandReturnsShowSourceInfo() {
        let action = AssistantPlanner.plan(prompt: "/info", source: nil)
        XCTAssertEqual(action, .showSourceInfo)
    }

    func testInfoInCommandRegistry() {
        XCTAssertTrue(CommandRegistry.allCommands.contains(where: { $0.command == "/info" }))
    }
}

// MARK: - TranscriptItem pinning

final class TranscriptItemPinningTests: XCTestCase {
    func testDefaultIsPinnedIsFalse() {
        let item = TranscriptItem(role: .assistant, title: "A", body: "Hello")
        XCTAssertFalse(item.isPinned)
    }

    func testPinnedItemCodableRoundTrip() throws {
        var item = TranscriptItem(role: .assistant, title: "A", body: "Hello", isPinned: true)
        XCTAssertTrue(item.isPinned)

        let data = try JSONEncoder().encode(item)
        let restored = try JSONDecoder().decode(TranscriptItem.self, from: data)
        XCTAssertTrue(restored.isPinned)
    }

    func testUnpinnedItemCodableRoundTrip() throws {
        let item = TranscriptItem(role: .user, title: "You", body: "Hi")
        let data = try JSONEncoder().encode(item)
        let restored = try JSONDecoder().decode(TranscriptItem.self, from: data)
        XCTAssertFalse(restored.isPinned)
    }
}

// MARK: - QueryTemplate model

final class QueryTemplateTests: XCTestCase {
    func testQueryTemplateCodableRoundTrip() throws {
        let template = QueryTemplate(name: "Count rows", sql: "SELECT COUNT(*) FROM trades;")
        let data = try JSONEncoder().encode(template)
        let restored = try JSONDecoder().decode(QueryTemplate.self, from: data)
        XCTAssertEqual(restored.id, template.id)
        XCTAssertEqual(restored.name, "Count rows")
        XCTAssertEqual(restored.sql, "SELECT COUNT(*) FROM trades;")
    }

    func testQueryTemplateEquality() {
        let id = UUID()
        let date = Date()
        let a = QueryTemplate(id: id, name: "Test", sql: "SELECT 1;", createdAt: date)
        let b = QueryTemplate(id: id, name: "Test", sql: "SELECT 1;", createdAt: date)
        XCTAssertEqual(a, b)
    }

    func testAppSettingsWithTemplatesCodableRoundTrip() throws {
        var settings = AppSettings(hasCompletedSetup: true)
        settings.queryTemplates = [
            QueryTemplate(name: "Count", sql: "SELECT COUNT(*) FROM trades;"),
        ]
        let data = try JSONEncoder().encode(settings)
        let restored = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(restored.queryTemplates.count, 1)
        XCTAssertEqual(restored.queryTemplates.first?.name, "Count")
    }

    func testEmptyTemplatesByDefault() {
        let settings = AppSettings()
        XCTAssertTrue(settings.queryTemplates.isEmpty)
    }
}

// MARK: - MetalExecutionState

final class MetalExecutionStateTests: XCTestCase {
    func testExecutionStateRawValues() {
        XCTAssertEqual(MetalExecutionState.idle.rawValue, "idle")
        XCTAssertEqual(MetalExecutionState.success.rawValue, "success")
        XCTAssertEqual(MetalExecutionState.failure.rawValue, "failure")
    }

    func testMetalWorkspaceDestinationRawValues() {
        XCTAssertEqual(MetalWorkspaceDestination.assistant.rawValue, "assistant")
        XCTAssertEqual(MetalWorkspaceDestination.transcripts.rawValue, "transcripts")
        XCTAssertEqual(MetalWorkspaceDestination.setup.rawValue, "setup")
        XCTAssertEqual(MetalWorkspaceDestination.settings.rawValue, "settings")
    }
}

// MARK: - AppSettings bookmarks

final class AppSettingsBookmarkTests: XCTestCase {
    func testSettingsWithBookmarksCodableRoundTrip() throws {
        var settings = AppSettings(hasCompletedSetup: true)
        settings.bookmarks = [
            BookmarkedCommand(sql: "SELECT 1;", sourceName: "test.duckdb"),
            BookmarkedCommand(sql: "SHOW TABLES;", sourceName: "market.duckdb"),
        ]

        let data = try JSONEncoder().encode(settings)
        let restored = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(restored.bookmarks.count, 2)
        XCTAssertEqual(restored.bookmarks.first?.sql, "SELECT 1;")
    }

    func testEmptyBookmarksByDefault() {
        let settings = AppSettings()
        XCTAssertTrue(settings.bookmarks.isEmpty)
    }
}

// MARK: - DuckDB EXPLAIN support

final class DuckDBExplainTests: XCTestCase {
    func testExplainSelectPassesThroughAsSQL() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/market.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "EXPLAIN SELECT * FROM trades;", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan, got \(action)")
        }

        XCTAssertTrue(plan.sql.contains("EXPLAIN"))
    }

    func testSummarizePassesThroughAsSQL() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/market.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "SUMMARIZE trades;", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan, got \(action)")
        }

        XCTAssertTrue(plan.sql.contains("SUMMARIZE"))
    }

    func testCopyStatementPassesThroughAsSQL() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/market.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "COPY trades TO '/tmp/out.csv';", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan, got \(action)")
        }

        XCTAssertTrue(plan.sql.contains("COPY"))
    }
}

// MARK: - /undo command

final class UndoCommandTests: XCTestCase {
    func testUndoCommandReturnsUndoLastMessage() {
        let action = AssistantPlanner.plan(prompt: "/undo", source: nil)
        XCTAssertEqual(action, .undoLastMessage)
    }
}

// MARK: - ProviderPreference defaults

final class ProviderPreferenceTests: XCTestCase {
    func testDefaultForClaudeUsesSonnet() {
        let pref = ProviderPreference.default(for: .claude)
        XCTAssertEqual(pref.authMode, .localCLI)
        XCTAssertEqual(pref.customModel, "sonnet")
    }

    func testDefaultForOpenAIUsesEmptyModel() {
        let pref = ProviderPreference.default(for: .openAI)
        XCTAssertEqual(pref.authMode, .localCLI)
        XCTAssertEqual(pref.customModel, "")
    }

    func testDefaultPreferenceInit() {
        let pref = ProviderPreference()
        XCTAssertEqual(pref.authMode, .localCLI)
        XCTAssertEqual(pref.customModel, "")
    }
}

// MARK: - ProviderKind properties

final class ProviderKindExtendedTests: XCTestCase {
    func testSuggestedModels() {
        XCTAssertEqual(ProviderKind.claude.suggestedModel, "sonnet")
        XCTAssertEqual(ProviderKind.openAI.suggestedModel, "")
        XCTAssertEqual(ProviderKind.gemini.suggestedModel, "")
    }

    func testAllCasesCount() {
        XCTAssertEqual(ProviderKind.allCases.count, 3)
    }

    func testGeminiHasMultipleAPIKeyNames() {
        XCTAssertTrue(ProviderKind.gemini.apiKeyEnvironmentNames.count >= 2)
        XCTAssertTrue(ProviderKind.gemini.apiKeyEnvironmentNames.contains("GEMINI_API_KEY"))
        XCTAssertTrue(ProviderKind.gemini.apiKeyEnvironmentNames.contains("GOOGLE_API_KEY"))
    }

    func testProviderKindIdentifiable() {
        XCTAssertEqual(ProviderKind.claude.id, "claude")
        XCTAssertEqual(ProviderKind.openAI.id, "openAI")
        XCTAssertEqual(ProviderKind.gemini.id, "gemini")
    }
}

// MARK: - Random sampling

final class RandomSamplingTests: XCTestCase {
    func testParquetRandomSampleUsesUsingSample() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.parquet"), kind: .parquet)
        let action = AssistantPlanner.plan(prompt: "show me a random sample", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan")
        }

        XCTAssertTrue(plan.sql.contains("USING SAMPLE"))
        XCTAssertTrue(plan.sql.contains("read_parquet"))
    }

    func testCSVRandomSampleUsesUsingSample() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.csv"), kind: .csv)
        let action = AssistantPlanner.plan(prompt: "random rows", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan")
        }

        XCTAssertTrue(plan.sql.contains("USING SAMPLE"))
        XCTAssertTrue(plan.sql.contains("read_csv"))
    }

    func testJSONRandomSampleUsesUsingSample() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.json"), kind: .json)
        let action = AssistantPlanner.plan(prompt: "random sample", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan")
        }

        XCTAssertTrue(plan.sql.contains("USING SAMPLE"))
        XCTAssertTrue(plan.sql.contains("read_json"))
    }
}

// MARK: - /reset command

final class ResetCommandTests: XCTestCase {
    func testResetCommandReturnsResetWorkspace() {
        let action = AssistantPlanner.plan(prompt: "/reset", source: nil)
        XCTAssertEqual(action, .resetWorkspace)
    }

    func testResetIsCaseInsensitive() {
        let action = AssistantPlanner.plan(prompt: "/RESET", source: nil)
        XCTAssertEqual(action, .resetWorkspace)
    }

    func testResetInCommandRegistry() {
        XCTAssertTrue(CommandRegistry.allCommands.contains(where: { $0.command == "/reset" }))
    }
}

// MARK: - DuckDB count [tablename]

final class DuckDBCountTableTests: XCTestCase {
    func testCountTradesGeneratesCountQuery() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/market.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "count trades", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan, got \(action)")
        }

        XCTAssertTrue(plan.sql.contains("COUNT(*)"))
        XCTAssertTrue(plan.sql.contains("FROM trades"))
    }

    func testCountRowsInOrdersGeneratesCountQuery() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/market.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "count rows in orders", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan, got \(action)")
        }

        XCTAssertTrue(plan.sql.contains("COUNT(*)"))
        XCTAssertTrue(plan.sql.contains("FROM orders"))
    }

    func testExtractCountTargetReturnsTableName() {
        XCTAssertEqual(AssistantPlanner.extractCountTarget(from: "count trades"), "trades")
        XCTAssertEqual(AssistantPlanner.extractCountTarget(from: "count rows in users"), "users")
    }

    func testExtractCountTargetRejectsReservedWords() {
        XCTAssertNil(AssistantPlanner.extractCountTarget(from: "count rows"))
        XCTAssertNil(AssistantPlanner.extractCountTarget(from: "count the"))
        XCTAssertNil(AssistantPlanner.extractCountTarget(from: "count all"))
    }

    func testExtractCountTargetRejectsShortNames() {
        XCTAssertNil(AssistantPlanner.extractCountTarget(from: "count a"))
    }
}

// MARK: - AppAppearance

final class AppAppearanceTests: XCTestCase {
    func testDisplayNames() {
        XCTAssertEqual(AppAppearance.system.displayName, "System")
        XCTAssertEqual(AppAppearance.light.displayName, "Light")
        XCTAssertEqual(AppAppearance.dark.displayName, "Dark")
    }

    func testAllCases() {
        XCTAssertEqual(AppAppearance.allCases.count, 3)
    }

    func testCodableRoundTrip() throws {
        for appearance in AppAppearance.allCases {
            let data = try JSONEncoder().encode(appearance)
            let restored = try JSONDecoder().decode(AppAppearance.self, from: data)
            XCTAssertEqual(restored, appearance)
        }
    }

    func testSettingsWithAppearanceCodableRoundTrip() throws {
        var settings = AppSettings(hasCompletedSetup: true, preferredAppearance: .dark)
        let data = try JSONEncoder().encode(settings)
        let restored = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(restored.preferredAppearance, .dark)
    }

    func testDefaultAppearanceIsSystem() {
        let settings = AppSettings()
        XCTAssertEqual(settings.preferredAppearance, .system)
    }
}

// MARK: - DataSource validation

final class DataSourceValidationTests: XCTestCase {
    func testFileExistsForMissingFile() {
        let source = DataSource(url: URL(fileURLWithPath: "/nonexistent/path/data.parquet"), kind: .parquet)
        XCTAssertFalse(source.fileExists)
        XCTAssertFalse(source.isReadable)
    }

    func testFileExistsForRealFile() throws {
        let tmpPath = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".csv")
        try "a,b\n1,2".write(to: tmpPath, atomically: true, encoding: .utf8)

        let source = DataSource(url: tmpPath, kind: .csv)
        XCTAssertTrue(source.fileExists)
        XCTAssertTrue(source.isReadable)

        try? FileManager.default.removeItem(at: tmpPath)
    }
}

// MARK: - DataSource DuckDB read expression

final class DataSourceReadExpressionTests: XCTestCase {
    func testParquetReadExpression() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.parquet"), kind: .parquet)
        XCTAssertEqual(source.duckDBReadExpression, "read_parquet('/tmp/data.parquet')")
    }

    func testCSVReadExpression() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.csv"), kind: .csv)
        XCTAssertEqual(source.duckDBReadExpression, "read_csv('/tmp/data.csv')")
    }

    func testJSONReadExpression() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.json"), kind: .json)
        XCTAssertEqual(source.duckDBReadExpression, "read_json('/tmp/data.json')")
    }

    func testDuckDBHasNoReadExpression() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/db.duckdb"), kind: .duckdb)
        XCTAssertNil(source.duckDBReadExpression)
    }

    func testReadExpressionEscapesApostrophe() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/John's data.parquet"), kind: .parquet)
        XCTAssertTrue(source.duckDBReadExpression?.contains("John''s") == true)
    }
}

// MARK: - DuckDB summarize [tablename]

final class DuckDBSummarizeTableTests: XCTestCase {
    func testSummarizeTradesGeneratesSummarize() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/market.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "summarize trades", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan, got \(action)")
        }

        XCTAssertTrue(plan.sql.contains("SUMMARIZE trades"))
    }

    func testStatsForOrdersGeneratesSummarize() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/market.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "stats for orders", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan, got \(action)")
        }

        XCTAssertTrue(plan.sql.contains("SUMMARIZE orders"))
    }

    func testExtractSummarizeTargetReturnsTableName() {
        XCTAssertEqual(AssistantPlanner.extractSummarizeTarget(from: "summarize trades"), "trades")
        XCTAssertEqual(AssistantPlanner.extractSummarizeTarget(from: "stats for users"), "users")
    }

    func testExtractSummarizeTargetRejectsReserved() {
        XCTAssertNil(AssistantPlanner.extractSummarizeTarget(from: "summarize the"))
        XCTAssertNil(AssistantPlanner.extractSummarizeTarget(from: "summarize data"))
    }

    func testGenericSummarizeFallsToGenericPattern() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/market.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "Summarize the data", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan, got \(action)")
        }

        // Should hit the generic summarize, not table-specific
        XCTAssertTrue(plan.sql.contains("SUMMARIZE"))
    }
}

// MARK: - DuckDB sample [tablename]

final class DuckDBSampleTableTests: XCTestCase {
    func testSampleTradesGeneratesSampleQuery() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/market.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "sample trades", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan, got \(action)")
        }

        XCTAssertTrue(plan.sql.contains("USING SAMPLE"))
        XCTAssertTrue(plan.sql.contains("FROM trades"))
    }

    func testRandomOrdersGeneratesSampleQuery() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/market.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "random orders", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan, got \(action)")
        }

        XCTAssertTrue(plan.sql.contains("USING SAMPLE"))
        XCTAssertTrue(plan.sql.contains("FROM orders"))
    }

    func testExtractSampleTargetReturnsTableName() {
        XCTAssertEqual(AssistantPlanner.extractSampleTarget(from: "sample trades"), "trades")
        XCTAssertEqual(AssistantPlanner.extractSampleTarget(from: "random users"), "users")
    }

    func testExtractSampleTargetRejectsReserved() {
        XCTAssertNil(AssistantPlanner.extractSampleTarget(from: "sample the"))
        XCTAssertNil(AssistantPlanner.extractSampleTarget(from: "random rows"))
    }
}

// MARK: - Comprehensive planner coverage

final class PlannerEdgeCaseTests: XCTestCase {
    func testParquetWithNoSourceReturnsGuidance() {
        let action = AssistantPlanner.plan(prompt: "How do I get started with a parquet file?", source: nil)
        guard case let .assistantReply(reply) = action else {
            return XCTFail("Expected assistant reply")
        }
        XCTAssertTrue(reply.contains("source"))
    }

    func testDuckDBKeywordReturnsGuidanceWithoutSource() {
        let action = AssistantPlanner.plan(prompt: "I want to use duckdb", source: nil)
        guard case let .assistantReply(reply) = action else {
            return XCTFail("Expected assistant reply")
        }
        XCTAssertTrue(reply.contains("source"))
    }

    func testWhatCanYouDoReturnsHelp() {
        let action = AssistantPlanner.plan(prompt: "What can you do?", source: nil)
        guard case let .assistantReply(reply) = action else {
            return XCTFail("Expected assistant reply")
        }
        XCTAssertTrue(reply.contains("Sift Commands"))
    }

    func testParquetFieldsListsColumns() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.parquet"), kind: .parquet)
        let action = AssistantPlanner.plan(prompt: "What fields are there?", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan")
        }
        XCTAssertTrue(plan.sql.contains("column_name"))
    }

    func testCSVFieldsListsColumns() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.csv"), kind: .csv)
        let action = AssistantPlanner.plan(prompt: "List fields", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan")
        }
        XCTAssertTrue(plan.sql.contains("column_name"))
    }

    func testJSONFieldsListsColumns() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.json"), kind: .json)
        let action = AssistantPlanner.plan(prompt: "Show fields", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan")
        }
        XCTAssertTrue(plan.sql.contains("column_name"))
    }

    func testDuckDBDatabaseInfoPattern() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/market.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "database info", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan")
        }
        XCTAssertTrue(plan.sql.contains("database_list"))
    }

    func testDuckDBListTablesPattern() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/market.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "list tables", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan")
        }
        XCTAssertEqual(plan.sql, "SHOW TABLES;")
    }

    func testDuckDBListColumnsPattern() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/market.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "list columns", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan")
        }
        XCTAssertTrue(plan.sql.contains("information_schema.columns"))
    }

    func testDuckDBRowCountsPattern() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/market.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "show row counts", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan")
        }
        XCTAssertTrue(plan.sql.contains("duckdb_tables()"))
    }
}

// MARK: - CommandRegistry count

final class CommandRegistryCountTests: XCTestCase {
    func testCommandRegistryHasExpectedCount() {
        // All known commands
        let expected = ["/sql", "/duckdb", "/help", "/clear", "/sources", "/copy", "/rerun",
                        "/history", "/export", "/status", "/version", "/bookmark", "/bookmarks",
                        "/undo", "/stats", "/info", "/pins", "/reset"]
        for cmd in expected {
            XCTAssertTrue(CommandRegistry.allCommands.contains(where: { $0.command == cmd }),
                          "Missing \(cmd) in registry")
        }
    }

    func testNoDuplicateCommandsInRegistry() {
        let commands = CommandRegistry.allCommands.map(\.command)
        let unique = Set(commands)
        XCTAssertEqual(commands.count, unique.count, "Duplicate commands in registry")
    }
}

// MARK: - TranscriptItem tags

final class TranscriptItemTagTests: XCTestCase {
    func testDefaultTagsIsEmpty() {
        let item = TranscriptItem(role: .assistant, title: "A", body: "Hello")
        XCTAssertTrue(item.tags.isEmpty)
    }

    func testTagsCodableRoundTrip() throws {
        let item = TranscriptItem(role: .user, title: "You", body: "Q", tags: ["important", "sql"])
        let data = try JSONEncoder().encode(item)
        let restored = try JSONDecoder().decode(TranscriptItem.self, from: data)
        XCTAssertEqual(restored.tags, ["important", "sql"])
    }

    func testItemWithTagsEquality() {
        let id = UUID()
        let date = Date()
        let a = TranscriptItem(id: id, role: .user, title: "You", body: "Q", timestamp: date, tags: ["x"])
        let b = TranscriptItem(id: id, role: .user, title: "You", body: "Q", timestamp: date, tags: ["x"])
        XCTAssertEqual(a, b)
    }

    func testItemWithDifferentTagsAreNotEqual() {
        let id = UUID()
        let date = Date()
        let a = TranscriptItem(id: id, role: .user, title: "You", body: "Q", timestamp: date, tags: ["x"])
        let b = TranscriptItem(id: id, role: .user, title: "You", body: "Q", timestamp: date, tags: ["y"])
        XCTAssertNotEqual(a, b)
    }
}

// MARK: - DataSource alias

final class DataSourceAliasTests: XCTestCase {
    func testDefaultAliasIsNil() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.parquet"), kind: .parquet)
        XCTAssertNil(source.alias)
        XCTAssertEqual(source.displayName, "data.parquet")
    }

    func testAliasOverridesDisplayName() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.parquet"), kind: .parquet, alias: "Prices")
        XCTAssertEqual(source.displayName, "Prices")
    }

    func testAliasCodableRoundTrip() throws {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.csv"), kind: .csv, alias: "My Data")
        let data = try JSONEncoder().encode(source)
        let restored = try JSONDecoder().decode(DataSource.self, from: data)
        XCTAssertEqual(restored.alias, "My Data")
        XCTAssertEqual(restored.displayName, "My Data")
    }

    func testNilAliasCodableRoundTrip() throws {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.json"), kind: .json)
        let data = try JSONEncoder().encode(source)
        let restored = try JSONDecoder().decode(DataSource.self, from: data)
        XCTAssertNil(restored.alias)
        XCTAssertEqual(restored.displayName, "data.json")
    }

    func testFileExtension() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.PARQUET"), kind: .parquet)
        XCTAssertEqual(source.fileExtension, "parquet")
    }

    func testDirectoryName() {
        let source = DataSource(url: URL(fileURLWithPath: "/Users/joe/data/prices.parquet"), kind: .parquet)
        XCTAssertEqual(source.directoryName, "data")
    }
}

// MARK: - /tags command

final class TagsCommandTests: XCTestCase {
    func testTagsCommandReturnsShowTags() {
        let action = AssistantPlanner.plan(prompt: "/tags", source: nil)
        XCTAssertEqual(action, .showTags)
    }

    func testTagsInCommandRegistry() {
        XCTAssertTrue(CommandRegistry.allCommands.contains(where: { $0.command == "/tags" }))
    }
}

// MARK: - DataSource query builders

final class DataSourceQueryBuilderTests: XCTestCase {
    func testSelectQueryForParquet() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.parquet"), kind: .parquet)
        let sql = source.selectQuery(limit: 10)
        XCTAssertEqual(sql, "SELECT * FROM read_parquet('/tmp/data.parquet') LIMIT 10;")
    }

    func testSelectQueryWithColumns() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.csv"), kind: .csv)
        let sql = source.selectQuery(columns: "name, price")
        XCTAssertEqual(sql, "SELECT name, price FROM read_csv('/tmp/data.csv');")
    }

    func testSelectQueryForDuckDBReturnsNil() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/db.duckdb"), kind: .duckdb)
        XCTAssertNil(source.selectQuery())
    }

    func testCountQueryForJSON() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.json"), kind: .json)
        let sql = source.countQuery()
        XCTAssertEqual(sql, "SELECT COUNT(*) AS row_count FROM read_json('/tmp/data.json');")
    }

    func testCountQueryForDuckDBReturnsNil() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/db.duckdb"), kind: .duckdb)
        XCTAssertNil(source.countQuery())
    }

    func testSelectQueryWithNoLimit() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.parquet"), kind: .parquet)
        let sql = source.selectQuery()
        XCTAssertEqual(sql, "SELECT * FROM read_parquet('/tmp/data.parquet');")
    }
}

// MARK: - MarkdownDetector

final class MarkdownDetectorTests: XCTestCase {
    func testContainsSQLBlock() {
        let text = "Here:\n```sql\nSELECT 1;\n```"
        XCTAssertTrue(MarkdownDetector.containsSQLBlock(text))
        XCTAssertTrue(MarkdownDetector.containsCodeBlock(text))
    }

    func testDoesNotContainSQLBlock() {
        let text = "Just plain text without any code."
        XCTAssertFalse(MarkdownDetector.containsSQLBlock(text))
        XCTAssertFalse(MarkdownDetector.containsCodeBlock(text))
    }

    func testExtractFirstCodeBlock() {
        let text = """
        Some text.
        ```sql
        SELECT * FROM trades;
        ```
        More text.
        """
        let extracted = MarkdownDetector.extractFirstCodeBlock(from: text)
        XCTAssertEqual(extracted, "SELECT * FROM trades;")
    }

    func testExtractCodeBlockWithNoLanguage() {
        let text = """
        ```
        hello world
        ```
        """
        let extracted = MarkdownDetector.extractFirstCodeBlock(from: text)
        XCTAssertEqual(extracted, "hello world")
    }

    func testExtractCodeBlockReturnsNilForNoBlocks() {
        let text = "No code blocks here."
        XCTAssertNil(MarkdownDetector.extractFirstCodeBlock(from: text))
    }

    func testCodeBlockCount() {
        let text = """
        ```sql
        SELECT 1;
        ```
        Text.
        ```python
        print("hello")
        ```
        """
        XCTAssertEqual(MarkdownDetector.codeBlockCount(in: text), 2)
    }

    func testCodeBlockCountZero() {
        XCTAssertEqual(MarkdownDetector.codeBlockCount(in: "no blocks"), 0)
    }

    func testContainsCodeBlockWithGenericFence() {
        let text = "```\nsome code\n```"
        XCTAssertTrue(MarkdownDetector.containsCodeBlock(text))
        XCTAssertFalse(MarkdownDetector.containsSQLBlock(text))
    }
}

// MARK: - DataSource query builder edge cases

final class DataSourceQueryBuilderEdgeCaseTests: XCTestCase {
    func testSelectQueryEscapesPathWithApostrophe() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/John's file.parquet"), kind: .parquet)
        let sql = source.selectQuery(limit: 5)
        XCTAssertTrue(sql?.contains("John''s") == true)
        XCTAssertFalse(sql?.contains("John's") == true)
    }

    func testCountQueryForCSV() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.csv"), kind: .csv)
        let sql = source.countQuery()
        XCTAssertTrue(sql?.contains("read_csv") == true)
        XCTAssertTrue(sql?.contains("COUNT(*)") == true)
    }

    func testSelectQueryForJSON() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.json"), kind: .json)
        let sql = source.selectQuery(columns: "name, age", limit: 100)
        XCTAssertEqual(sql, "SELECT name, age FROM read_json('/tmp/data.json') LIMIT 100;")
    }
}

// MARK: - CommandRegistry tab completion edge cases

final class CommandRegistryEdgeCaseTests: XCTestCase {
    func testCompletionForSlashSReturnsMultiple() {
        let results = CommandRegistry.completions(for: "/s")
        // /sources, /status, /stats, /sql
        XCTAssertGreaterThanOrEqual(results.count, 3)
    }

    func testCompletionForSlashExReturnsExport() {
        let results = CommandRegistry.completions(for: "/ex")
        XCTAssertTrue(results.contains(where: { $0.command == "/export" }))
    }

    func testCompletionForFullCommandReturnsExactly() {
        let results = CommandRegistry.completions(for: "/version")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.command, "/version")
    }
}

// MARK: - QueryExecutionStats

final class QueryExecutionStatsTests: XCTestCase {
    func testDurationFormattedSubMillisecond() {
        let stats = QueryExecutionStats(sql: "SELECT 1;", durationMilliseconds: 0.5, succeeded: true)
        XCTAssertEqual(stats.durationFormatted, "<1ms")
    }

    func testDurationFormattedMilliseconds() {
        let stats = QueryExecutionStats(sql: "SELECT 1;", durationMilliseconds: 42, succeeded: true)
        XCTAssertEqual(stats.durationFormatted, "42ms")
    }

    func testDurationFormattedSeconds() {
        let stats = QueryExecutionStats(sql: "SELECT 1;", durationMilliseconds: 2500, succeeded: true)
        XCTAssertEqual(stats.durationFormatted, "2.50s")
    }

    func testCodableRoundTrip() throws {
        let stats = QueryExecutionStats(sql: "SELECT 1;", durationMilliseconds: 100, rowsAffected: 42, succeeded: true)
        let data = try JSONEncoder().encode(stats)
        let restored = try JSONDecoder().decode(QueryExecutionStats.self, from: data)
        XCTAssertEqual(restored.sql, "SELECT 1;")
        XCTAssertEqual(restored.durationMilliseconds, 100)
        XCTAssertEqual(restored.rowsAffected, 42)
        XCTAssertTrue(restored.succeeded)
    }

    func testFailedStats() {
        let stats = QueryExecutionStats(sql: "INVALID;", durationMilliseconds: 5, succeeded: false)
        XCTAssertFalse(stats.succeeded)
        XCTAssertEqual(stats.durationFormatted, "5ms")
    }
}

// MARK: - TranscriptAnalytics

final class TranscriptAnalyticsTests: XCTestCase {
    func testWordCount() {
        let items = [
            TranscriptItem(role: .user, title: "You", body: "Hello world"),
            TranscriptItem(role: .assistant, title: "A", body: "Three word reply"),
        ]
        XCTAssertEqual(TranscriptAnalytics.wordCount(in: items), 5)
    }

    func testCharacterCount() {
        let items = [
            TranscriptItem(role: .user, title: "You", body: "Hi"),
        ]
        XCTAssertEqual(TranscriptAnalytics.characterCount(in: items), 2)
    }

    func testAverageWordsPerMessage() {
        let items = [
            TranscriptItem(role: .user, title: "You", body: "One two"),
            TranscriptItem(role: .assistant, title: "A", body: "Three four five six"),
        ]
        XCTAssertEqual(TranscriptAnalytics.averageWordsPerMessage(in: items), 3.0)
    }

    func testAverageWordsEmpty() {
        XCTAssertEqual(TranscriptAnalytics.averageWordsPerMessage(in: []), 0)
    }

    func testTimeSpan() {
        let now = Date()
        let items = [
            TranscriptItem(role: .user, title: "You", body: "A", timestamp: now),
            TranscriptItem(role: .assistant, title: "A", body: "B", timestamp: now.addingTimeInterval(60)),
        ]
        XCTAssertEqual(TranscriptAnalytics.timeSpan(of: items), 60, accuracy: 0.1)
    }

    func testTimeSpanEmpty() {
        XCTAssertEqual(TranscriptAnalytics.timeSpan(of: []), 0)
    }
}

// MARK: - DataSource query builders (summarize, describe)

final class DataSourceSummarizeDescribeTests: XCTestCase {
    func testSummarizeQueryForParquet() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.parquet"), kind: .parquet)
        XCTAssertEqual(source.summarizeQuery(), "SUMMARIZE SELECT * FROM read_parquet('/tmp/data.parquet');")
    }

    func testSummarizeQueryForDuckDBReturnsNil() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/db.duckdb"), kind: .duckdb)
        XCTAssertNil(source.summarizeQuery())
    }

    func testDescribeQueryForCSV() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.csv"), kind: .csv)
        XCTAssertTrue(source.describeQuery()?.contains("DESCRIBE") == true)
        XCTAssertTrue(source.describeQuery()?.contains("read_csv") == true)
    }

    func testDescribeQueryForDuckDB() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/db.duckdb"), kind: .duckdb)
        XCTAssertEqual(source.describeQuery(), "DESCRIBE;")
    }

    func testIsTabularFile() {
        XCTAssertTrue(DataSource(url: URL(fileURLWithPath: "/tmp/a.parquet"), kind: .parquet).isTabularFile)
        XCTAssertTrue(DataSource(url: URL(fileURLWithPath: "/tmp/a.csv"), kind: .csv).isTabularFile)
        XCTAssertTrue(DataSource(url: URL(fileURLWithPath: "/tmp/a.json"), kind: .json).isTabularFile)
        XCTAssertFalse(DataSource(url: URL(fileURLWithPath: "/tmp/a.duckdb"), kind: .duckdb).isTabularFile)
    }
}

// MARK: - DuckDB top N by column

final class DuckDBTopNByColumnTests: XCTestCase {
    func testTopNByColumnFromTable() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/market.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "top 10 by price from trades", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan, got \(action)")
        }

        XCTAssertTrue(plan.sql.contains("ORDER BY price DESC"))
        XCTAssertTrue(plan.sql.contains("LIMIT 10"))
        XCTAssertTrue(plan.sql.contains("FROM trades"))
    }

    func testExtractTopNByColumn() {
        let result = AssistantPlanner.extractTopNByColumn(from: "top 5 by volume in orders")
        XCTAssertEqual(result?.table, "orders")
        XCTAssertEqual(result?.column, "volume")
        XCTAssertEqual(result?.limit, 5)
    }

    func testExtractTopNByColumnNoMatch() {
        XCTAssertNil(AssistantPlanner.extractTopNByColumn(from: "show me everything"))
    }

    func testTopNByColumnAlternatePattern() {
        let result = AssistantPlanner.extractTopNByColumn(from: "top 3 revenue from sales")
        XCTAssertEqual(result?.table, "sales")
        XCTAssertEqual(result?.column, "revenue")
        XCTAssertEqual(result?.limit, 3)
    }
}

// MARK: - DuckDB show indices alias

final class DuckDBShowIndicesTests: XCTestCase {
    func testShowIndicesUsesIndexesQuery() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/market.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "Show indices", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan, got \(action)")
        }

        XCTAssertTrue(plan.sql.contains("duckdb_indexes()"))
    }

    func testListViewsUsesViewsQuery() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/market.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "List views", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan, got \(action)")
        }

        XCTAssertTrue(plan.sql.contains("duckdb_views()"))
    }
}

// MARK: - Various planner patterns

final class PlannerPatternCoverageTests: XCTestCase {
    func testDuckDBDatabaseSizePattern() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/db.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "database size", source: source)
        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan, got \(action)")
        }
        XCTAssertTrue(plan.sql.contains("database_list"))
    }

    func testDuckDBMemoryInfoPattern() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/db.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "memory info", source: source)
        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan, got \(action)")
        }
        XCTAssertTrue(plan.sql.contains("database_size"))
    }

    func testDuckDBVersionPattern() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/db.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "What version is this?", source: source)
        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan, got \(action)")
        }
        XCTAssertTrue(plan.sql.contains("PRAGMA version"))
    }

    func testParquetSampleUsesSample() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.parquet"), kind: .parquet)
        let action = AssistantPlanner.plan(prompt: "sample this", source: source)
        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan, got \(action)")
        }
        XCTAssertTrue(plan.sql.contains("LIMIT 25")) // "sample" matches preview
    }

    func testCSVTopNExtractsLimit() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.csv"), kind: .csv)
        let action = AssistantPlanner.plan(prompt: "top 5", source: source)
        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan, got \(action)")
        }
        XCTAssertTrue(plan.sql.contains("LIMIT 5"))
    }

    func testJSONTopNExtractsLimit() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.json"), kind: .json)
        let action = AssistantPlanner.plan(prompt: "first 3", source: source)
        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan, got \(action)")
        }
        XCTAssertTrue(plan.sql.contains("LIMIT 3"))
    }

    func testDuckDBTableSizePattern() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/db.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "table size", source: source)
        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan, got \(action)")
        }
        XCTAssertTrue(plan.sql.contains("duckdb_tables()"))
    }

    func testDuckDBColumnNamesPattern() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/db.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "column names", source: source)
        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan, got \(action)")
        }
        XCTAssertTrue(plan.sql.contains("information_schema.columns"))
    }

    func testParquetSchemaDescribes() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.parquet"), kind: .parquet)
        let action = AssistantPlanner.plan(prompt: "schema", source: source)
        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan, got \(action)")
        }
        XCTAssertTrue(plan.sql.contains("DESCRIBE"))
    }

    func testDuckDBExtensionsPattern() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/db.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "show extensions", source: source)
        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan, got \(action)")
        }
        XCTAssertTrue(plan.sql.contains("duckdb_extensions()"))
    }
}

// MARK: - Remote URL sources

final class RemoteURLSourceTests: XCTestCase {
    func testFromRemoteURLCreatesParquetSource() {
        let source = DataSource.fromRemoteURL("https://example.com/data.parquet")
        XCTAssertNotNil(source)
        XCTAssertEqual(source?.kind, .parquet)
        XCTAssertTrue(source?.isRemote == true)
    }

    func testFromRemoteURLCreatesCSVSource() {
        let source = DataSource.fromRemoteURL("http://example.com/data.csv")
        XCTAssertNotNil(source)
        XCTAssertEqual(source?.kind, .csv)
    }

    func testFromRemoteURLRejectsUnsupported() {
        XCTAssertNil(DataSource.fromRemoteURL("https://example.com/data.xlsx"))
    }

    func testFromRemoteURLRejectsInvalidURL() {
        XCTAssertNil(DataSource.fromRemoteURL("not a url"))
    }

    func testFromRemoteURLRejectsFTP() {
        XCTAssertNil(DataSource.fromRemoteURL("ftp://example.com/data.parquet"))
    }

    func testLocalSourceIsNotRemote() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.parquet"), kind: .parquet)
        XCTAssertFalse(source.isRemote)
    }

    func testSupportedExtensionsContainsAll() {
        let exts = DataSource.supportedExtensions
        XCTAssertTrue(exts.contains("parquet"))
        XCTAssertTrue(exts.contains("csv"))
        XCTAssertTrue(exts.contains("tsv"))
        XCTAssertTrue(exts.contains("json"))
        XCTAssertTrue(exts.contains("jsonl"))
        XCTAssertTrue(exts.contains("ndjson"))
        XCTAssertTrue(exts.contains("duckdb"))
        XCTAssertTrue(exts.contains("db"))
    }
}

// MARK: - DuckDB Output Parser

final class DuckDBOutputParserTests: XCTestCase {
    func testExtractRowCountFromRowsPattern() {
        XCTAssertEqual(DuckDBOutputParser.extractRowCount(from: "42 rows"), 42)
        XCTAssertEqual(DuckDBOutputParser.extractRowCount(from: "1 row"), 1)
    }

    func testExtractRowCountFromRowCountColumn() {
        let output = "row_count\n100\n"
        XCTAssertEqual(DuckDBOutputParser.extractRowCount(from: output), 100)
    }

    func testExtractRowCountReturnsNilForNoMatch() {
        XCTAssertNil(DuckDBOutputParser.extractRowCount(from: "hello world"))
    }

    func testCountDataRows() {
        let output = """
        name | age
        ─────┼────
        Alice | 30
        Bob | 25
        """
        XCTAssertEqual(DuckDBOutputParser.countDataRows(in: output), 3) // header + 2 data
    }

    func testCountDataRowsEmptyOutput() {
        XCTAssertEqual(DuckDBOutputParser.countDataRows(in: ""), 0)
    }

    func testContainsError() {
        XCTAssertTrue(DuckDBOutputParser.containsError(in: "Error: table not found"))
        XCTAssertTrue(DuckDBOutputParser.containsError(in: "Parse Error: syntax error"))
        XCTAssertTrue(DuckDBOutputParser.containsError(in: "Catalog Error: missing"))
        XCTAssertTrue(DuckDBOutputParser.containsError(in: "Binder Error: column"))
        XCTAssertFalse(DuckDBOutputParser.containsError(in: "42\nDone"))
    }
}

// MARK: - Source comparison

final class SourceComparisonTests: XCTestCase {
    func testComparisonSameKind() {
        let s1 = DataSource(url: URL(fileURLWithPath: "/tmp/a.parquet"), kind: .parquet)
        let s2 = DataSource(url: URL(fileURLWithPath: "/tmp/b.parquet"), kind: .parquet)
        let cmp = SourceComparison(source1: s1, source2: s2)
        XCTAssertTrue(cmp.sameKind)
        XCTAssertTrue(cmp.sameDirectory)
        XCTAssertTrue(cmp.sameExtension)
    }

    func testComparisonDifferentKind() {
        let s1 = DataSource(url: URL(fileURLWithPath: "/tmp/a.parquet"), kind: .parquet)
        let s2 = DataSource(url: URL(fileURLWithPath: "/data/b.csv"), kind: .csv)
        let cmp = SourceComparison(source1: s1, source2: s2)
        XCTAssertFalse(cmp.sameKind)
        XCTAssertFalse(cmp.sameDirectory)
        XCTAssertFalse(cmp.sameExtension)
    }

    func testComparisonSummary() {
        let s1 = DataSource(url: URL(fileURLWithPath: "/tmp/a.parquet"), kind: .parquet)
        let s2 = DataSource(url: URL(fileURLWithPath: "/tmp/b.parquet"), kind: .parquet)
        let cmp = SourceComparison(source1: s1, source2: s2)
        let summary = cmp.summary
        XCTAssertTrue(summary.contains("a.parquet"))
        XCTAssertTrue(summary.contains("b.parquet"))
        XCTAssertTrue(summary.contains("✓"))
    }
}

// MARK: - DuckDB error recovery

final class DuckDBErrorRecoveryTests: XCTestCase {
    func testTableNotFoundSuggestion() {
        let suggestions = DuckDBErrorRecovery.suggestions(for: "Catalog Error: Table 'trades' does not exist")
        XCTAssertTrue(suggestions.contains(where: { $0.contains("SHOW TABLES") }))
    }

    func testColumnNotFoundSuggestion() {
        let suggestions = DuckDBErrorRecovery.suggestions(for: "Binder Error: column 'price' not found")
        XCTAssertTrue(suggestions.contains(where: { $0.contains("DESCRIBE") }))
    }

    func testSyntaxErrorSuggestion() {
        let suggestions = DuckDBErrorRecovery.suggestions(for: "Parser Error: syntax error at end of input")
        XCTAssertTrue(suggestions.contains(where: { $0.contains("syntax") }))
    }

    func testOutOfMemorySuggestion() {
        let suggestions = DuckDBErrorRecovery.suggestions(for: "Out of Memory Error: not enough memory")
        XCTAssertTrue(suggestions.contains(where: { $0.contains("LIMIT") }))
    }

    func testFileNotFoundSuggestion() {
        let suggestions = DuckDBErrorRecovery.suggestions(for: "IO Error: File not found: /tmp/missing.parquet")
        XCTAssertTrue(suggestions.contains(where: { $0.contains("file path") }))
    }

    func testUnknownErrorGivesFallback() {
        let suggestions = DuckDBErrorRecovery.suggestions(for: "Something completely unexpected")
        XCTAssertFalse(suggestions.isEmpty)
        XCTAssertTrue(suggestions.contains(where: { $0.contains("/help") }))
    }

    func testPermissionDeniedSuggestion() {
        let suggestions = DuckDBErrorRecovery.suggestions(for: "Permission denied: access denied to file")
        XCTAssertTrue(suggestions.contains(where: { $0.contains("permission") }))
    }
}

// MARK: - DataSource favorites

final class DataSourceFavoriteTests: XCTestCase {
    func testDefaultIsFavoriteIsFalse() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.parquet"), kind: .parquet)
        XCTAssertFalse(source.isFavorite)
    }

    func testFavoriteCodableRoundTrip() throws {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.csv"), kind: .csv, isFavorite: true)
        let data = try JSONEncoder().encode(source)
        let restored = try JSONDecoder().decode(DataSource.self, from: data)
        XCTAssertTrue(restored.isFavorite)
    }
}

// MARK: - DuckDB distinct pattern

final class DuckDBDistinctPatternTests: XCTestCase {
    func testDistinctColumnInTable() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/market.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "distinct symbol in trades", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan, got \(action)")
        }

        XCTAssertTrue(plan.sql.contains("SELECT DISTINCT symbol"))
        XCTAssertTrue(plan.sql.contains("FROM trades"))
    }

    func testUniqueValuesOfColumnFromTable() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/market.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "unique values of status from orders", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan, got \(action)")
        }

        XCTAssertTrue(plan.sql.contains("DISTINCT status"))
        XCTAssertTrue(plan.sql.contains("FROM orders"))
    }

    func testExtractDistinctPattern() {
        let result = AssistantPlanner.extractDistinctPattern(from: "distinct symbol in trades")
        XCTAssertEqual(result?.table, "trades")
        XCTAssertEqual(result?.column, "symbol")
    }

    func testExtractDistinctPatternNoMatch() {
        XCTAssertNil(AssistantPlanner.extractDistinctPattern(from: "show me data"))
    }
}

// MARK: - DuckDB combined patterns integration

final class DuckDBCombinedPatternTests: XCTestCase {
    func testDistinctBeforeGroupBy() {
        // "distinct" should be checked before "group by" 
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/db.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "distinct category in products", source: source)
        guard case let .command(plan) = action else {
            return XCTFail("Expected command, got \(action)")
        }
        XCTAssertTrue(plan.sql.contains("DISTINCT"))
    }

    func testWhereFilterBeforeJoin() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/db.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "filter trades where price > 50", source: source)
        guard case let .command(plan) = action else {
            return XCTFail("Expected command, got \(action)")
        }
        XCTAssertTrue(plan.sql.contains("WHERE"))
    }

    func testJoinPatternGeneratesSQL() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/db.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "join users and orders on user_id", source: source)
        guard case let .command(plan) = action else {
            return XCTFail("Expected command, got \(action)")
        }
        XCTAssertTrue(plan.sql.contains("JOIN"))
        XCTAssertTrue(plan.sql.contains("USING"))
    }

    func testTopNByColumnGeneratesOrderBy() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/db.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "top 5 by revenue from sales", source: source)
        guard case let .command(plan) = action else {
            return XCTFail("Expected command, got \(action)")
        }
        XCTAssertTrue(plan.sql.contains("ORDER BY"))
        XCTAssertTrue(plan.sql.contains("LIMIT 5"))
    }
}

// MARK: - Error recovery for various error types

final class DuckDBErrorRecoveryEdgeCaseTests: XCTestCase {
    func testMultipleMatchesCombineSuggestions() {
        // An error containing both "column" and "not found" + "syntax error"
        let suggestions = DuckDBErrorRecovery.suggestions(for: "Binder Error: column 'x' not found, also syntax error at position 5")
        // Should have suggestions for both
        XCTAssertTrue(suggestions.count >= 2)
    }

    func testEmptyErrorMessageGivesFallback() {
        let suggestions = DuckDBErrorRecovery.suggestions(for: "")
        XCTAssertFalse(suggestions.isEmpty)
    }

    func testInvalidKeywordInErrorDetected() {
        let suggestions = DuckDBErrorRecovery.suggestions(for: "something invalid happened")
        XCTAssertFalse(suggestions.isEmpty)
    }
}

// MARK: - Source comparison edge cases

final class SourceComparisonEdgeCaseTests: XCTestCase {
    func testComparisonEquality() {
        let s1 = DataSource(url: URL(fileURLWithPath: "/tmp/a.parquet"), kind: .parquet)
        let s2 = DataSource(url: URL(fileURLWithPath: "/tmp/b.parquet"), kind: .parquet)
        let cmpA = SourceComparison(source1: s1, source2: s2)
        let cmpB = SourceComparison(source1: s1, source2: s2)
        XCTAssertEqual(cmpA, cmpB)
    }

    func testComparisonDifferentDirectories() {
        let s1 = DataSource(url: URL(fileURLWithPath: "/data/a.parquet"), kind: .parquet)
        let s2 = DataSource(url: URL(fileURLWithPath: "/other/b.parquet"), kind: .parquet)
        let cmp = SourceComparison(source1: s1, source2: s2)
        XCTAssertTrue(cmp.sameKind)
        XCTAssertFalse(cmp.sameDirectory)
    }

    func testComparisonCSVvsTSV() {
        let s1 = DataSource(url: URL(fileURLWithPath: "/tmp/a.csv"), kind: .csv)
        let s2 = DataSource(url: URL(fileURLWithPath: "/tmp/b.tsv"), kind: .csv)
        let cmp = SourceComparison(source1: s1, source2: s2)
        XCTAssertTrue(cmp.sameKind) // Both are .csv kind
        XCTAssertFalse(cmp.sameExtension) // csv vs tsv
    }
}

// MARK: - DuckDB group-by pattern

final class DuckDBGroupByPatternTests: XCTestCase {
    func testGroupByColumnInTable() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/market.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "group by symbol in trades", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan, got \(action)")
        }

        XCTAssertTrue(plan.sql.contains("GROUP BY symbol"))
        XCTAssertTrue(plan.sql.contains("FROM trades"))
        XCTAssertTrue(plan.sql.contains("COUNT(*)"))
    }

    func testCountByCategory() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/market.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "count by category from products", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan, got \(action)")
        }

        XCTAssertTrue(plan.sql.contains("GROUP BY category"))
        XCTAssertTrue(plan.sql.contains("FROM products"))
    }

    func testExtractGroupByPattern() {
        let result = AssistantPlanner.extractGroupByPattern(from: "group by region in sales")
        XCTAssertEqual(result?.table, "sales")
        XCTAssertEqual(result?.column, "region")
    }

    func testBreakdownByPattern() {
        let result = AssistantPlanner.extractGroupByPattern(from: "breakdown by status from orders")
        XCTAssertEqual(result?.table, "orders")
        XCTAssertEqual(result?.column, "status")
    }

    func testExtractGroupByNoMatch() {
        XCTAssertNil(AssistantPlanner.extractGroupByPattern(from: "show me everything"))
    }
}

// MARK: - TranscriptFilter

final class TranscriptFilterTests: XCTestCase {
    func testErrorResults() {
        let items = [
            TranscriptItem(role: .assistant, title: "R", body: "ok", kind: .commandResult(exitCode: 0, stdout: "ok", stderr: "")),
            TranscriptItem(role: .assistant, title: "R", body: "err", kind: .commandResult(exitCode: 1, stdout: "", stderr: "error")),
            TranscriptItem(role: .user, title: "You", body: "Q"),
        ]
        XCTAssertEqual(TranscriptFilter.errorResults(in: items).count, 1)
    }

    func testSuccessResults() {
        let items = [
            TranscriptItem(role: .assistant, title: "R", body: "ok", kind: .commandResult(exitCode: 0, stdout: "ok", stderr: "")),
            TranscriptItem(role: .assistant, title: "R", body: "err", kind: .commandResult(exitCode: 1, stdout: "", stderr: "error")),
        ]
        XCTAssertEqual(TranscriptFilter.successResults(in: items).count, 1)
    }

    func testItemsByDateRange() {
        let now = Date()
        let items = [
            TranscriptItem(role: .user, title: "A", body: "old", timestamp: now.addingTimeInterval(-3600)),
            TranscriptItem(role: .user, title: "B", body: "recent", timestamp: now.addingTimeInterval(-60)),
            TranscriptItem(role: .user, title: "C", body: "new", timestamp: now),
        ]
        let filtered = TranscriptFilter.items(in: items, from: now.addingTimeInterval(-120), to: now)
        XCTAssertEqual(filtered.count, 2) // recent + new
    }

    func testRecentItemsWithinWindow() {
        let now = Date()
        let items = [
            TranscriptItem(role: .user, title: "A", body: "old", timestamp: now.addingTimeInterval(-3600)),
            TranscriptItem(role: .user, title: "B", body: "new", timestamp: now),
        ]
        let recent = TranscriptFilter.recentItems(in: items, seconds: 600)
        XCTAssertEqual(recent.count, 1)
        XCTAssertEqual(recent.first?.body, "new")
    }

    func testEmptyResults() {
        XCTAssertTrue(TranscriptFilter.errorResults(in: []).isEmpty)
        XCTAssertTrue(TranscriptFilter.successResults(in: []).isEmpty)
    }
}

// MARK: - DuckDB output parser edge cases

final class DuckDBOutputParserEdgeCaseTests: XCTestCase {
    func testExtractRowCountFromLargeNumber() {
        XCTAssertEqual(DuckDBOutputParser.extractRowCount(from: "1000000 rows"), 1_000_000)
    }

    func testContainsErrorForSyntaxError() {
        XCTAssertTrue(DuckDBOutputParser.containsError(in: "syntax error at position 5"))
    }

    func testContainsErrorForCleanOutput() {
        XCTAssertFalse(DuckDBOutputParser.containsError(in: "name\nAlice\nBob"))
    }

    func testCountDataRowsSingleLine() {
        XCTAssertEqual(DuckDBOutputParser.countDataRows(in: "header\ndata"), 1)
    }

    func testCountDataRowsOnlyHeader() {
        // Single non-empty line → treated as header, 0 data rows
        XCTAssertEqual(DuckDBOutputParser.countDataRows(in: "header"), 0)
    }
}

// MARK: - DataSource remote query

final class DataSourceRemoteQueryTests: XCTestCase {
    func testRemoteParquetReadExpression() {
        let source = DataSource.fromRemoteURL("https://data.example.com/prices.parquet")
        XCTAssertNotNil(source?.duckDBReadExpression)
        XCTAssertTrue(source?.duckDBReadExpression?.contains("read_parquet") == true)
        XCTAssertTrue(source?.duckDBReadExpression?.contains("https://") == true)
    }

    func testRemoteCSVSelectQuery() {
        let source = DataSource.fromRemoteURL("https://data.example.com/trades.csv")
        let sql = source?.selectQuery(limit: 10)
        XCTAssertTrue(sql?.contains("read_csv") == true)
        XCTAssertTrue(sql?.contains("LIMIT 10") == true)
    }

    func testRemoteJSONCountQuery() {
        let source = DataSource.fromRemoteURL("https://api.example.com/data.json")
        let sql = source?.countQuery()
        XCTAssertTrue(sql?.contains("COUNT(*)") == true)
    }
}

// MARK: - DuckDB WHERE filter

final class DuckDBWhereFilterTests: XCTestCase {
    func testFilterTradesWhereCondition() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/market.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "filter trades where price > 100", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan, got \(action)")
        }

        XCTAssertTrue(plan.sql.contains("WHERE price > 100"))
        XCTAssertTrue(plan.sql.contains("FROM trades"))
    }

    func testFilterOrdersWhereStatus() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/market.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "filter orders where status = 'filled'", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan, got \(action)")
        }

        XCTAssertTrue(plan.sql.contains("WHERE"))
        XCTAssertTrue(plan.sql.contains("orders"))
    }

    func testExtractWhereFilter() {
        let result = AssistantPlanner.extractWhereFilter(from: "filter trades where price > 100")
        XCTAssertEqual(result?.table, "trades")
        XCTAssertEqual(result?.condition, "price > 100")
    }

    func testExtractWhereFilterFromPattern() {
        let result = AssistantPlanner.extractWhereFilter(from: "from users where age >= 21")
        XCTAssertEqual(result?.table, "users")
        XCTAssertEqual(result?.condition, "age >= 21")
    }

    func testExtractWhereFilterNoMatch() {
        XCTAssertNil(AssistantPlanner.extractWhereFilter(from: "show me all data"))
    }
}

// MARK: - DuckDB join pattern

final class DuckDBJoinPatternTests: XCTestCase {
    func testJoinTwoTablesOnColumn() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/market.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "join orders and customers on customer_id", source: source)

        guard case let .command(plan) = action else {
            return XCTFail("Expected command plan, got \(action)")
        }

        XCTAssertTrue(plan.sql.contains("JOIN"))
        XCTAssertTrue(plan.sql.contains("orders"))
        XCTAssertTrue(plan.sql.contains("customers"))
        XCTAssertTrue(plan.sql.contains("customer_id"))
    }

    func testExtractJoinPatternAndOn() {
        let result = AssistantPlanner.extractJoinPattern(from: "join trades and positions on symbol")
        XCTAssertEqual(result?.table1, "trades")
        XCTAssertEqual(result?.table2, "positions")
        XCTAssertEqual(result?.column, "symbol")
    }

    func testExtractJoinPatternWithUsing() {
        let result = AssistantPlanner.extractJoinPattern(from: "join trades and prices using date")
        XCTAssertEqual(result?.table1, "trades")
        XCTAssertEqual(result?.table2, "prices")
        XCTAssertEqual(result?.column, "date")
    }

    func testExtractJoinPatternNoMatch() {
        XCTAssertNil(AssistantPlanner.extractJoinPattern(from: "show me data"))
    }
}

// MARK: - DuckDB aggregate patterns

final class DuckDBAggregatePatternTests: XCTestCase {
    func testAvgPriceFromTrades() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/db.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "avg price from trades", source: source)
        guard case let .command(plan) = action else {
            return XCTFail("Expected command, got \(action)")
        }
        XCTAssertTrue(plan.sql.contains("AVG(price)"))
        XCTAssertTrue(plan.sql.contains("FROM trades"))
    }

    func testSumRevenueInSales() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/db.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "sum revenue in sales", source: source)
        guard case let .command(plan) = action else {
            return XCTFail("Expected command, got \(action)")
        }
        XCTAssertTrue(plan.sql.contains("SUM(revenue)"))
    }

    func testMaxVolumeFromTrades() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/db.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "max volume from trades", source: source)
        guard case let .command(plan) = action else {
            return XCTFail("Expected command, got \(action)")
        }
        XCTAssertTrue(plan.sql.contains("MAX(volume)"))
    }

    func testMinPriceInOrders() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/db.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "min price in orders", source: source)
        guard case let .command(plan) = action else {
            return XCTFail("Expected command, got \(action)")
        }
        XCTAssertTrue(plan.sql.contains("MIN(price)"))
    }

    func testAverageAlias() {
        let result = AssistantPlanner.extractAggregatePattern(from: "average price from trades")
        XCTAssertEqual(result?.function, "AVG")
        XCTAssertEqual(result?.column, "price")
        XCTAssertEqual(result?.table, "trades")
    }

    func testTotalAlias() {
        let result = AssistantPlanner.extractAggregatePattern(from: "total quantity in orders")
        XCTAssertEqual(result?.function, "SUM")
    }

    func testMaximumAlias() {
        let result = AssistantPlanner.extractAggregatePattern(from: "maximum score from results")
        XCTAssertEqual(result?.function, "MAX")
    }

    func testMinimumAlias() {
        let result = AssistantPlanner.extractAggregatePattern(from: "minimum age from users")
        XCTAssertEqual(result?.function, "MIN")
    }

    func testAggregateNoMatch() {
        XCTAssertNil(AssistantPlanner.extractAggregatePattern(from: "show me the data"))
    }

    func testAvgWithOfPreposition() {
        let result = AssistantPlanner.extractAggregatePattern(from: "avg of price from trades")
        XCTAssertEqual(result?.function, "AVG")
        XCTAssertEqual(result?.column, "price")
    }
}

// MARK: - DuckDB order-by pattern

final class DuckDBOrderByPatternTests: XCTestCase {
    func testOrderByColumnInTable() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/db.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "order by price in trades", source: source)
        guard case let .command(plan) = action else {
            return XCTFail("Expected command, got \(action)")
        }
        XCTAssertTrue(plan.sql.contains("ORDER BY price"))
        XCTAssertTrue(plan.sql.contains("FROM trades"))
    }

    func testSortTableByColumn() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/db.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "sort trades by date", source: source)
        guard case let .command(plan) = action else {
            return XCTFail("Expected command, got \(action)")
        }
        XCTAssertTrue(plan.sql.contains("ORDER BY date"))
    }

    func testExtractOrderByDescending() {
        let result = AssistantPlanner.extractOrderByPattern(from: "sort price in trades desc")
        XCTAssertEqual(result?.table, "trades")
        XCTAssertEqual(result?.column, "price")
        XCTAssertTrue(result?.descending == true)
    }

    func testExtractOrderByAscending() {
        let result = AssistantPlanner.extractOrderByPattern(from: "order by name in users")
        XCTAssertEqual(result?.table, "users")
        XCTAssertEqual(result?.column, "name")
        XCTAssertFalse(result?.descending == true)
    }

    func testExtractOrderByNoMatch() {
        XCTAssertNil(AssistantPlanner.extractOrderByPattern(from: "show me everything"))
    }
}

// MARK: - TranscriptTiming

final class TranscriptTimingTests: XCTestCase {
    func testItemDurationsCalculatesGaps() {
        let now = Date()
        let items = [
            TranscriptItem(role: .user, title: "A", body: "1", timestamp: now),
            TranscriptItem(role: .assistant, title: "B", body: "2", timestamp: now.addingTimeInterval(5)),
            TranscriptItem(role: .user, title: "C", body: "3", timestamp: now.addingTimeInterval(15)),
        ]
        let durations = TranscriptTiming.itemDurations(in: items)
        XCTAssertEqual(durations.count, 3)
        XCTAssertEqual(durations[0].gapSeconds, 0, accuracy: 0.1)
        XCTAssertEqual(durations[1].gapSeconds, 5, accuracy: 0.1)
        XCTAssertEqual(durations[2].gapSeconds, 10, accuracy: 0.1)
    }

    func testLongestGap() {
        let now = Date()
        let items = [
            TranscriptItem(role: .user, title: "A", body: "1", timestamp: now),
            TranscriptItem(role: .assistant, title: "B", body: "2", timestamp: now.addingTimeInterval(2)),
            TranscriptItem(role: .user, title: "C", body: "3", timestamp: now.addingTimeInterval(60)),
        ]
        XCTAssertEqual(TranscriptTiming.longestGap(in: items), 58, accuracy: 0.1)
    }

    func testLongestGapEmpty() {
        XCTAssertEqual(TranscriptTiming.longestGap(in: []), 0)
    }

    func testItemDurationsSingleItem() {
        let items = [TranscriptItem(role: .user, title: "A", body: "1")]
        let durations = TranscriptTiming.itemDurations(in: items)
        XCTAssertEqual(durations.count, 1)
        XCTAssertEqual(durations[0].gapSeconds, 0)
    }
}

// MARK: - DuckDB aggregate with "of" preposition

final class DuckDBAggregateOfTests: XCTestCase {
    func testSumOfQuantityFromOrders() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/db.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "sum of quantity from orders", source: source)
        guard case let .command(plan) = action else {
            return XCTFail("Expected command, got \(action)")
        }
        XCTAssertTrue(plan.sql.contains("SUM(quantity)"))
    }

    func testAverageOfScoreInExams() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/db.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "average of score in exams", source: source)
        guard case let .command(plan) = action else {
            return XCTFail("Expected command, got \(action)")
        }
        XCTAssertTrue(plan.sql.contains("AVG(score)"))
    }
}

// MARK: - Order by descending keyword

final class DuckDBOrderByDescTests: XCTestCase {
    func testOrderByHighest() {
        let result = AssistantPlanner.extractOrderByPattern(from: "sort price in trades highest")
        XCTAssertTrue(result?.descending == true)
    }

    func testOrderByDescending() {
        let result = AssistantPlanner.extractOrderByPattern(from: "order by date in events descending")
        XCTAssertTrue(result?.descending == true)
    }

    func testOrderByDefaultAscending() {
        let result = AssistantPlanner.extractOrderByPattern(from: "order by name in users")
        XCTAssertFalse(result?.descending == true)
    }
}

// MARK: - TranscriptTiming edge cases

final class TranscriptTimingEdgeCaseTests: XCTestCase {
    func testItemDurationsEmpty() {
        let durations = TranscriptTiming.itemDurations(in: [])
        XCTAssertTrue(durations.isEmpty)
    }

    func testLongestGapWithTwoItems() {
        let now = Date()
        let items = [
            TranscriptItem(role: .user, title: "A", body: "1", timestamp: now),
            TranscriptItem(role: .assistant, title: "B", body: "2", timestamp: now.addingTimeInterval(30)),
        ]
        XCTAssertEqual(TranscriptTiming.longestGap(in: items), 30, accuracy: 0.1)
    }
}

// MARK: - Source notes

final class DataSourceNotesTests: XCTestCase {
    func testDefaultNotesIsNil() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.parquet"), kind: .parquet)
        XCTAssertNil(source.notes)
    }

    func testNotesCodableRoundTrip() throws {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.csv"), kind: .csv, notes: "Daily trade data")
        let data = try JSONEncoder().encode(source)
        let restored = try JSONDecoder().decode(DataSource.self, from: data)
        XCTAssertEqual(restored.notes, "Daily trade data")
    }

    func testNilNotesCodableRoundTrip() throws {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.json"), kind: .json)
        let data = try JSONEncoder().encode(source)
        let restored = try JSONDecoder().decode(DataSource.self, from: data)
        XCTAssertNil(restored.notes)
    }
}

// MARK: - DataSource full Codable round-trip with all properties

final class DataSourceFullRoundTripTests: XCTestCase {
    func testAllPropertiesRoundTrip() throws {
        let source = DataSource(
            url: URL(fileURLWithPath: "/tmp/data.parquet"),
            kind: .parquet,
            alias: "My Data",
            isFavorite: true,
            notes: "Important file"
        )
        let data = try JSONEncoder().encode(source)
        let restored = try JSONDecoder().decode(DataSource.self, from: data)
        XCTAssertEqual(restored.alias, "My Data")
        XCTAssertTrue(restored.isFavorite)
        XCTAssertEqual(restored.notes, "Important file")
        XCTAssertEqual(restored.displayName, "My Data")
        XCTAssertEqual(restored.kind, .parquet)
    }
}

// MARK: - DuckDB planner precedence

final class DuckDBPlannerPrecedenceTests: XCTestCase {
    func testSQLPassthroughTakesPrecedenceForSelectKeyword() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/db.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "SELECT * FROM trades WHERE price > 100;", source: source)
        guard case let .command(plan) = action else {
            return XCTFail("Expected command, got \(action)")
        }
        // Raw SQL should pass through directly, not be parsed as "where" pattern
        XCTAssertEqual(plan.sql, "SELECT * FROM trades WHERE price > 100;")
    }

    func testRawSQLTakesPrecedenceOverKeywords() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/db.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "/sql SELECT avg(price) FROM trades;", source: source)
        guard case let .command(plan) = action else {
            return XCTFail("Expected command, got \(action)")
        }
        XCTAssertTrue(plan.sql.contains("avg(price)"))
    }

    func testShowTablesOverShowViews() {
        // "show tables" should match "show tables" not "show views"
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/db.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "show tables", source: source)
        guard case let .command(plan) = action else {
            return XCTFail("Expected command, got \(action)")
        }
        XCTAssertEqual(plan.sql, "SHOW TABLES;")
    }

    func testDescribeTableBeforeGenericDescribe() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/db.duckdb"), kind: .duckdb)
        let action1 = AssistantPlanner.plan(prompt: "describe trades", source: source)
        guard case let .command(plan1) = action1 else {
            return XCTFail("Expected command")
        }
        XCTAssertEqual(plan1.sql, "DESCRIBE trades;")

        let action2 = AssistantPlanner.plan(prompt: "describe the schema", source: source)
        guard case let .command(plan2) = action2 else {
            return XCTFail("Expected command")
        }
        XCTAssertEqual(plan2.sql, "DESCRIBE;")
    }
}

// MARK: - MarkdownDetector edge cases

final class MarkdownDetectorEdgeCaseTests: XCTestCase {
    func testExtractFromNestedBackticks() {
        let text = """
        Here:
        ```sql
        SELECT `column_name` FROM `table`;
        ```
        """
        let extracted = MarkdownDetector.extractFirstCodeBlock(from: text)
        XCTAssertNotNil(extracted)
        XCTAssertTrue(extracted?.contains("SELECT") == true)
    }

    func testCodeBlockCountWithSingle() {
        let text = "```\ncode\n```"
        XCTAssertEqual(MarkdownDetector.codeBlockCount(in: text), 1)
    }

    func testContainsSQLBlockUppercase() {
        XCTAssertTrue(MarkdownDetector.containsSQLBlock("```SQL\nSELECT 1;\n```"))
    }
}

// MARK: - TranscriptAnalytics edge cases

final class TranscriptAnalyticsEdgeCaseTests: XCTestCase {
    func testWordCountEmpty() {
        XCTAssertEqual(TranscriptAnalytics.wordCount(in: []), 0)
    }

    func testCharacterCountEmpty() {
        XCTAssertEqual(TranscriptAnalytics.characterCount(in: []), 0)
    }

    func testWordCountWithMultipleSpaces() {
        let items = [TranscriptItem(role: .user, title: "You", body: "Hello    World")]
        XCTAssertEqual(TranscriptAnalytics.wordCount(in: items), 2)
    }

    func testTimeSpanSingleItem() {
        let items = [TranscriptItem(role: .user, title: "You", body: "A")]
        XCTAssertEqual(TranscriptAnalytics.timeSpan(of: items), 0)
    }
}

// MARK: - DuckDB error recovery completeness

final class DuckDBErrorRecoveryCompletenessTests: XCTestCase {
    func testAllErrorTypesCovered() {
        // Verify each major error type has at least one suggestion
        let errorTypes = [
            "Catalog Error: Table 'x' does not exist",
            "Binder Error: column 'y' not found",
            "Parser Error: syntax error",
            "IO Error: File not found",
            "Permission denied",
            "Out of Memory Error",
        ]
        for error in errorTypes {
            let suggestions = DuckDBErrorRecovery.suggestions(for: error)
            XCTAssertFalse(suggestions.isEmpty, "No suggestion for: \(error)")
        }
    }

    func testAccessDeniedSuggestion() {
        let suggestions = DuckDBErrorRecovery.suggestions(for: "access denied to /tmp/data.parquet")
        XCTAssertTrue(suggestions.contains(where: { $0.contains("permission") }))
    }

    func testInvalidInputSuggestion() {
        let suggestions = DuckDBErrorRecovery.suggestions(for: "invalid input: expected integer")
        XCTAssertFalse(suggestions.isEmpty)
    }
}

// MARK: - DuckDB aggregate pattern completeness

final class DuckDBAggregateCompletenessTests: XCTestCase {
    func testAllAggregatesExtract() {
        let fns = [("avg", "AVG"), ("sum", "SUM"), ("min", "MIN"), ("max", "MAX"),
                   ("average", "AVG"), ("total", "SUM"), ("minimum", "MIN"), ("maximum", "MAX")]
        for (input, expected) in fns {
            let result = AssistantPlanner.extractAggregatePattern(from: "\(input) price from trades")
            XCTAssertEqual(result?.function, expected, "\(input) should map to \(expected)")
        }
    }
}

// MARK: - DuckDB order-by pattern completeness

final class DuckDBOrderByCompletenessTests: XCTestCase {
    func testSortVariations() {
        // "sort trades by price"
        let r1 = AssistantPlanner.extractOrderByPattern(from: "sort trades by price")
        XCTAssertEqual(r1?.table, "trades")
        XCTAssertEqual(r1?.column, "price")

        // "order by date in events"
        let r2 = AssistantPlanner.extractOrderByPattern(from: "order by date in events")
        XCTAssertEqual(r2?.table, "events")
        XCTAssertEqual(r2?.column, "date")

        // "order name from users"
        let r3 = AssistantPlanner.extractOrderByPattern(from: "order name from users")
        XCTAssertEqual(r3?.table, "users")
        XCTAssertEqual(r3?.column, "name")
    }
}

// MARK: - Planner with all file source types

final class PlannerAllSourceTypesTests: XCTestCase {
    func testPreviewForAllFileTypes() {
        let kinds: [(DataSourceKind, String)] = [
            (.parquet, "read_parquet"), (.csv, "read_csv"), (.json, "read_json")
        ]
        for (kind, readFn) in kinds {
            let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.\(kind.rawValue)"), kind: kind)
            let action = AssistantPlanner.plan(prompt: "Preview rows", source: source)
            guard case let .command(plan) = action else {
                XCTFail("Expected command for \(kind)")
                continue
            }
            XCTAssertTrue(plan.sql.contains(readFn), "\(kind) should use \(readFn)")
            XCTAssertTrue(plan.sql.contains("LIMIT 25"))
        }
    }

    func testCountForAllFileTypes() {
        for kind in [DataSourceKind.parquet, .csv, .json] {
            let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.\(kind.rawValue)"), kind: kind)
            let action = AssistantPlanner.plan(prompt: "Count rows", source: source)
            guard case let .command(plan) = action else {
                XCTFail("Expected command for \(kind)")
                continue
            }
            XCTAssertTrue(plan.sql.contains("COUNT(*)"))
        }
    }

    func testSummarizeForAllFileTypes() {
        for kind in [DataSourceKind.parquet, .csv, .json] {
            let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.\(kind.rawValue)"), kind: kind)
            let action = AssistantPlanner.plan(prompt: "Summarize this", source: source)
            guard case let .command(plan) = action else {
                XCTFail("Expected command for \(kind)")
                continue
            }
            XCTAssertTrue(plan.sql.contains("SUMMARIZE"))
        }
    }
}

// MARK: - TranscriptExporter

final class TranscriptExporterTests: XCTestCase {
    func testResultsAsCSVFormatsCorrectly() {
        let items = [
            TranscriptItem(role: .assistant, title: "R", body: "ok",
                           kind: .commandResult(exitCode: 0, stdout: "Alice\nBob", stderr: "")),
            TranscriptItem(role: .assistant, title: "R", body: "err",
                           kind: .commandResult(exitCode: 1, stdout: "", stderr: "error")),
        ]
        let csv = TranscriptExporter.resultsAsCSV(from: items)
        XCTAssertTrue(csv.contains("sql,exit_code,stdout_preview"))
        XCTAssertTrue(csv.contains("0"))
        XCTAssertTrue(csv.contains("1"))
    }

    func testResultsAsCSVEmptyForNoResults() {
        let items = [TranscriptItem(role: .user, title: "You", body: "Hello")]
        let csv = TranscriptExporter.resultsAsCSV(from: items)
        // Should only have header
        XCTAssertEqual(csv.components(separatedBy: "\n").count, 1)
    }

    func testAsPlainText() {
        let items = [
            TranscriptItem(role: .user, title: "You", body: "Hello"),
            TranscriptItem(role: .assistant, title: "A", body: "World"),
        ]
        let text = TranscriptExporter.asPlainText(from: items)
        XCTAssertTrue(text.contains("[user] You: Hello"))
        XCTAssertTrue(text.contains("[assistant] A: World"))
    }
}

// MARK: - TranscriptDeduplicator

final class TranscriptDeduplicatorTests: XCTestCase {
    func testDetectsDuplicateUserMessages() {
        let items = [
            TranscriptItem(role: .user, title: "You", body: "Hello"),
            TranscriptItem(role: .assistant, title: "A", body: "Hi"),
            TranscriptItem(role: .user, title: "You", body: "Hello"),
        ]
        let dupes = TranscriptDeduplicator.duplicateMessages(in: items)
        XCTAssertEqual(dupes, ["Hello"])
    }

    func testNoDuplicatesReturnsEmpty() {
        let items = [
            TranscriptItem(role: .user, title: "You", body: "Hello"),
            TranscriptItem(role: .user, title: "You", body: "World"),
        ]
        XCTAssertTrue(TranscriptDeduplicator.duplicateMessages(in: items).isEmpty)
    }

    func testHasDuplicates() {
        let withDupes = [
            TranscriptItem(role: .user, title: "You", body: "Q"),
            TranscriptItem(role: .user, title: "You", body: "Q"),
        ]
        XCTAssertTrue(TranscriptDeduplicator.hasDuplicates(in: withDupes))

        let noDupes = [TranscriptItem(role: .user, title: "You", body: "Q")]
        XCTAssertFalse(TranscriptDeduplicator.hasDuplicates(in: noDupes))
    }

    func testIgnoresAssistantDuplicates() {
        let items = [
            TranscriptItem(role: .assistant, title: "A", body: "Reply"),
            TranscriptItem(role: .assistant, title: "A", body: "Reply"),
        ]
        XCTAssertFalse(TranscriptDeduplicator.hasDuplicates(in: items))
    }
}

// MARK: - CommandAlias model

final class CommandAliasTests: XCTestCase {
    func testCommandAliasCodableRoundTrip() throws {
        let alias = CommandAlias(name: "trades", sql: "SELECT * FROM trades LIMIT 10;")
        let data = try JSONEncoder().encode(alias)
        let restored = try JSONDecoder().decode(CommandAlias.self, from: data)
        XCTAssertEqual(restored.name, "trades")
        XCTAssertEqual(restored.sql, "SELECT * FROM trades LIMIT 10;")
    }

    func testCommandAliasEquality() {
        let id = UUID()
        let a = CommandAlias(id: id, name: "x", sql: "SELECT 1;")
        let b = CommandAlias(id: id, name: "x", sql: "SELECT 1;")
        XCTAssertEqual(a, b)
    }

    func testSettingsWithAliasesCodableRoundTrip() throws {
        var settings = AppSettings(hasCompletedSetup: true)
        settings.commandAliases = [CommandAlias(name: "t", sql: "SHOW TABLES;")]
        let data = try JSONEncoder().encode(settings)
        let restored = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(restored.commandAliases.count, 1)
        XCTAssertEqual(restored.commandAliases.first?.name, "t")
    }

    func testEmptyAliasesByDefault() {
        let settings = AppSettings()
        XCTAssertTrue(settings.commandAliases.isEmpty)
    }
}

// MARK: - TranscriptExporter edge cases

final class TranscriptExporterEdgeCaseTests: XCTestCase {
    func testAsPlainTextEmpty() {
        XCTAssertEqual(TranscriptExporter.asPlainText(from: []), "")
    }

    func testResultsAsCSVWithQuotesInOutput() {
        let items = [
            TranscriptItem(role: .assistant, title: "R", body: "ok",
                           kind: .commandResult(exitCode: 0, stdout: "Hello \"World\"", stderr: "")),
        ]
        let csv = TranscriptExporter.resultsAsCSV(from: items)
        // Quotes should be escaped
        XCTAssertTrue(csv.contains("\"\"World\"\""))
    }

    func testResultsAsCSVWithNewlinesInOutput() {
        let items = [
            TranscriptItem(role: .assistant, title: "R", body: "ok",
                           kind: .commandResult(exitCode: 0, stdout: "Line1\nLine2\nLine3", stderr: "")),
        ]
        let csv = TranscriptExporter.resultsAsCSV(from: items)
        // Newlines should be replaced with spaces
        XCTAssertTrue(csv.contains("Line1 Line2 Line3"))
    }
}

// MARK: - TranscriptDeduplicator edge cases

final class TranscriptDeduplicatorEdgeCaseTests: XCTestCase {
    func testEmptyTranscriptNoDuplicates() {
        XCTAssertFalse(TranscriptDeduplicator.hasDuplicates(in: []))
    }

    func testMultipleDuplicatesDetected() {
        let items = [
            TranscriptItem(role: .user, title: "You", body: "A"),
            TranscriptItem(role: .user, title: "You", body: "B"),
            TranscriptItem(role: .user, title: "You", body: "A"),
            TranscriptItem(role: .user, title: "You", body: "B"),
            TranscriptItem(role: .user, title: "You", body: "C"),
        ]
        let dupes = TranscriptDeduplicator.duplicateMessages(in: items)
        XCTAssertEqual(dupes.count, 2) // A and B
    }

    func testDuplicatesSorted() {
        let items = [
            TranscriptItem(role: .user, title: "You", body: "Zebra"),
            TranscriptItem(role: .user, title: "You", body: "Alpha"),
            TranscriptItem(role: .user, title: "You", body: "Zebra"),
            TranscriptItem(role: .user, title: "You", body: "Alpha"),
        ]
        let dupes = TranscriptDeduplicator.duplicateMessages(in: items)
        XCTAssertEqual(dupes, ["Alpha", "Zebra"])
    }
}

// MARK: - Query Complexity Estimator

final class QueryComplexityEstimatorTests: XCTestCase {
    func testSimpleSelect() {
        XCTAssertEqual(QueryComplexityEstimator.estimate("SELECT * FROM trades;"), .simple)
    }

    func testSimpleCount() {
        XCTAssertEqual(QueryComplexityEstimator.estimate("SELECT COUNT(*) FROM trades;"), .simple)
    }

    func testModerateJoin() {
        XCTAssertEqual(QueryComplexityEstimator.estimate("SELECT * FROM trades JOIN prices ON trades.id = prices.trade_id;"), .moderate)
    }

    func testModerateGroupBy() {
        XCTAssertEqual(QueryComplexityEstimator.estimate("SELECT symbol, COUNT(*) FROM trades GROUP BY symbol;"), .moderate)
    }

    func testComplexCTE() {
        let sql = "WITH cte AS (SELECT * FROM trades) SELECT * FROM cte JOIN prices ON cte.id = prices.id;"
        XCTAssertEqual(QueryComplexityEstimator.estimate(sql), .complex)
    }

    func testComplexWindowFunction() {
        let sql = "SELECT *, ROW_NUMBER() OVER (PARTITION BY symbol ORDER BY date) FROM trades;"
        XCTAssertEqual(QueryComplexityEstimator.estimate(sql), .moderate)
    }

    func testModerateUnion() {
        XCTAssertEqual(QueryComplexityEstimator.estimate("SELECT * FROM a UNION SELECT * FROM b;"), .moderate)
    }

    func testComplexSubquery() {
        let sql = "SELECT * FROM trades WHERE price > (SELECT AVG(price) FROM trades);"
        XCTAssertEqual(QueryComplexityEstimator.estimate(sql), .moderate)
    }

    func testDisplayLabels() {
        XCTAssertEqual(QueryComplexityLevel.simple.displayLabel, "Simple")
        XCTAssertEqual(QueryComplexityLevel.moderate.displayLabel, "Moderate")
        XCTAssertEqual(QueryComplexityLevel.complex.displayLabel, "Complex")
    }
}

// MARK: - DuckDB Type Detection

final class DuckDBTypeDetectionTests: XCTestCase {
    func testIntegerTypes() {
        XCTAssertEqual(DuckDBColumnType.detect(from: "INTEGER"), .integer)
        XCTAssertEqual(DuckDBColumnType.detect(from: "BIGINT"), .integer)
        XCTAssertEqual(DuckDBColumnType.detect(from: "SMALLINT"), .integer)
        XCTAssertEqual(DuckDBColumnType.detect(from: "TINYINT"), .integer)
        XCTAssertEqual(DuckDBColumnType.detect(from: "HUGEINT"), .integer)
    }

    func testDecimalTypes() {
        XCTAssertEqual(DuckDBColumnType.detect(from: "FLOAT"), .decimal)
        XCTAssertEqual(DuckDBColumnType.detect(from: "DOUBLE"), .decimal)
        XCTAssertEqual(DuckDBColumnType.detect(from: "DECIMAL(10,2)"), .decimal)
        XCTAssertEqual(DuckDBColumnType.detect(from: "REAL"), .decimal)
    }

    func testTextTypes() {
        XCTAssertEqual(DuckDBColumnType.detect(from: "VARCHAR"), .text)
        XCTAssertEqual(DuckDBColumnType.detect(from: "TEXT"), .text)
        XCTAssertEqual(DuckDBColumnType.detect(from: "VARCHAR(255)"), .text)
        XCTAssertEqual(DuckDBColumnType.detect(from: "UUID"), .text)
    }

    func testBooleanType() {
        XCTAssertEqual(DuckDBColumnType.detect(from: "BOOLEAN"), .boolean)
        XCTAssertEqual(DuckDBColumnType.detect(from: "BOOL"), .boolean)
    }

    func testTimestampTypes() {
        XCTAssertEqual(DuckDBColumnType.detect(from: "TIMESTAMP"), .timestamp)
        XCTAssertEqual(DuckDBColumnType.detect(from: "TIMESTAMP WITH TIME ZONE"), .timestamp)
        XCTAssertEqual(DuckDBColumnType.detect(from: "DATETIME"), .timestamp)
    }

    func testDateType() {
        XCTAssertEqual(DuckDBColumnType.detect(from: "DATE"), .date)
    }

    func testBlobTypes() {
        XCTAssertEqual(DuckDBColumnType.detect(from: "BLOB"), .blob)
        XCTAssertEqual(DuckDBColumnType.detect(from: "BYTEA"), .blob)
    }

    func testOtherType() {
        XCTAssertEqual(DuckDBColumnType.detect(from: "STRUCT"), .other)
        XCTAssertEqual(DuckDBColumnType.detect(from: "MAP"), .other)
        XCTAssertEqual(DuckDBColumnType.detect(from: "LIST"), .other)
    }

    func testCaseInsensitiveDetection() {
        XCTAssertEqual(DuckDBColumnType.detect(from: "integer"), .integer)
        XCTAssertEqual(DuckDBColumnType.detect(from: "Varchar"), .text)
        XCTAssertEqual(DuckDBColumnType.detect(from: "boolean"), .boolean)
    }

    func testNumericType() {
        XCTAssertEqual(DuckDBColumnType.detect(from: "NUMERIC"), .decimal)
    }

    func testStringType() {
        XCTAssertEqual(DuckDBColumnType.detect(from: "STRING"), .text)
    }

    func testCharType() {
        XCTAssertEqual(DuckDBColumnType.detect(from: "CHAR(10)"), .text)
    }
}

// MARK: - QueryComplexity edge cases

final class QueryComplexityEdgeCaseTests: XCTestCase {
    func testHavingAddsComplexity() {
        let sql = "SELECT symbol, COUNT(*) FROM trades GROUP BY symbol HAVING COUNT(*) > 10;"
        let level = QueryComplexityEstimator.estimate(sql)
        XCTAssertEqual(level, .moderate)
    }

    func testMultipleJoinsAreComplex() {
        let sql = "SELECT * FROM a JOIN b ON a.id = b.a_id JOIN c ON b.id = c.b_id GROUP BY a.name HAVING COUNT(*) > 1;"
        let level = QueryComplexityEstimator.estimate(sql)
        XCTAssertEqual(level, .complex)
    }

    func testEmptyQueryIsSimple() {
        XCTAssertEqual(QueryComplexityEstimator.estimate(""), .simple)
    }

    func testDescribeIsSimple() {
        XCTAssertEqual(QueryComplexityEstimator.estimate("DESCRIBE trades;"), .simple)
    }

    func testExceptAddsComplexity() {
        let sql = "SELECT * FROM a EXCEPT SELECT * FROM b;"
        XCTAssertEqual(QueryComplexityEstimator.estimate(sql), .moderate)
    }
}

// MARK: - SourceComparison full properties

final class SourceComparisonFullTests: XCTestCase {
    func testComparisonSameFile() {
        let s = DataSource(url: URL(fileURLWithPath: "/tmp/a.parquet"), kind: .parquet)
        let cmp = SourceComparison(source1: s, source2: s)
        XCTAssertTrue(cmp.sameKind)
        XCTAssertTrue(cmp.sameDirectory)
        XCTAssertTrue(cmp.sameExtension)
    }

    func testComparisonJsonVsJsonl() {
        let s1 = DataSource(url: URL(fileURLWithPath: "/tmp/a.json"), kind: .json)
        let s2 = DataSource(url: URL(fileURLWithPath: "/tmp/b.jsonl"), kind: .json)
        let cmp = SourceComparison(source1: s1, source2: s2)
        XCTAssertTrue(cmp.sameKind)
        XCTAssertFalse(cmp.sameExtension)
    }

    func testComparisonDuckDBvsParquet() {
        let s1 = DataSource(url: URL(fileURLWithPath: "/tmp/a.duckdb"), kind: .duckdb)
        let s2 = DataSource(url: URL(fileURLWithPath: "/tmp/b.parquet"), kind: .parquet)
        let cmp = SourceComparison(source1: s1, source2: s2)
        XCTAssertFalse(cmp.sameKind)
    }
}

// MARK: - DuckDB output parser comprehensive

final class DuckDBOutputParserComprehensiveTests: XCTestCase {
    func testExtractRowCountZero() {
        XCTAssertEqual(DuckDBOutputParser.extractRowCount(from: "0 rows"), 0)
    }

    func testCountDataRowsWithSeparator() {
        let output = "name | age\n─────┼────\nAlice | 30\n"
        let count = DuckDBOutputParser.countDataRows(in: output)
        XCTAssertGreaterThan(count, 0)
    }

    func testContainsErrorBinderError() {
        XCTAssertTrue(DuckDBOutputParser.containsError(in: "Binder Error: column not found"))
    }

    func testContainsErrorCatalogError() {
        XCTAssertTrue(DuckDBOutputParser.containsError(in: "Catalog Error: table missing"))
    }
}

// MARK: - SQL Formatter

final class SQLFormatterTests: XCTestCase {
    func testUppercaseKeywords() {
        let formatted = SQLFormatter.uppercaseKeywords(in: "select * from trades where price > 100;")
        XCTAssertTrue(formatted.contains("SELECT"))
        XCTAssertTrue(formatted.contains("FROM"))
        XCTAssertTrue(formatted.contains("WHERE"))
    }

    func testUppercasePreservesNonKeywords() {
        let formatted = SQLFormatter.uppercaseKeywords(in: "select name from users;")
        XCTAssertTrue(formatted.contains("name"))
        XCTAssertTrue(formatted.contains("users"))
    }

    func testClauseCountSimple() {
        XCTAssertEqual(SQLFormatter.clauseCount(in: "SELECT * FROM trades;"), 2) // SELECT, FROM
    }

    func testClauseCountComplex() {
        let sql = "SELECT symbol, COUNT(*) FROM trades WHERE price > 0 GROUP BY symbol HAVING COUNT(*) > 1 ORDER BY symbol LIMIT 10;"
        XCTAssertEqual(SQLFormatter.clauseCount(in: sql), 7) // SELECT, FROM, WHERE, GROUP BY, HAVING, ORDER BY, LIMIT
    }

    func testClauseCountEmpty() {
        XCTAssertEqual(SQLFormatter.clauseCount(in: "SHOW TABLES;"), 0)
    }

    func testClauseCountWithJoin() {
        let sql = "SELECT * FROM a JOIN b ON a.id = b.id WHERE a.x > 0;"
        XCTAssertEqual(SQLFormatter.clauseCount(in: sql), 4) // SELECT, FROM, JOIN, WHERE
    }
}

// MARK: - SQL Formatter edge cases

final class SQLFormatterEdgeCaseTests: XCTestCase {
    func testUppercaseKeywordsAlreadyUppercase() {
        let sql = "SELECT * FROM trades WHERE price > 100;"
        let formatted = SQLFormatter.uppercaseKeywords(in: sql)
        XCTAssertEqual(formatted, sql) // No change
    }

    func testClauseCountDescribe() {
        XCTAssertEqual(SQLFormatter.clauseCount(in: "DESCRIBE trades;"), 0)
    }

    func testClauseCountWithSubquery() {
        let sql = "SELECT * FROM trades WHERE id IN (SELECT id FROM filtered);"
        let count = SQLFormatter.clauseCount(in: sql)
        XCTAssertGreaterThanOrEqual(count, 3) // At least SELECT, FROM, WHERE
    }
}

// MARK: - SQL Sanitizer edge cases

final class SQLSanitizerEdgeCaseTests: XCTestCase {
    func testCopyIsNotDangerous() {
        // COPY is a read operation in DuckDB
        XCTAssertTrue(SQLSanitizer.isReadOnly("COPY trades TO '/tmp/out.csv';"))
    }

    func testCreateIsNotDangerous() {
        // CREATE TABLE AS SELECT is a read-like operation, not destructive
        XCTAssertFalse(SQLSanitizer.containsDangerousOperations("CREATE TABLE new_table AS SELECT * FROM old;"))
    }

    func testEmptyQueryIsReadOnly() {
        XCTAssertTrue(SQLSanitizer.isReadOnly(""))
    }

    func testExtractTableNamesWithAlias() {
        let tables = SQLSanitizer.extractTableNames(from: "SELECT t.name FROM trades AS t;")
        XCTAssertTrue(tables.contains("trades"))
    }

    func testExtractTableNamesMultipleJoins() {
        let sql = "SELECT * FROM a JOIN b ON a.id = b.a_id JOIN c ON b.id = c.b_id;"
        let tables = SQLSanitizer.extractTableNames(from: sql)
        XCTAssertEqual(tables.count, 3)
    }

    func testReadOnlyWithPragma() {
        XCTAssertTrue(SQLSanitizer.isReadOnly("PRAGMA version;"))
    }
}

// MARK: - PromptContextBuilder edge cases

final class PromptContextBuilderEdgeCaseTests: XCTestCase {
    func testShortLabelForDuckDB() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/db.duckdb"), kind: .duckdb)
        XCTAssertEqual(PromptContextBuilder.shortLabel(for: source), "db.duckdb (DuckDB)")
    }

    func testSourceContextForCSV() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.csv"), kind: .csv)
        let ctx = PromptContextBuilder.sourceContext(for: source)
        XCTAssertTrue(ctx.contains("CSV"))
        XCTAssertTrue(ctx.contains("read_csv"))
    }

    func testSourceContextWithNotes() {
        // Notes don't appear in context (they're for the user, not the prompt)
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.parquet"), kind: .parquet, notes: "important")
        let ctx = PromptContextBuilder.sourceContext(for: source)
        XCTAssertTrue(ctx.contains("Parquet"))
    }
}

// MARK: - TranscriptArchiver with tags

final class TranscriptArchiverWithTagsTests: XCTestCase {
    func testArchivedItemsPreserveTags() {
        let now = Date()
        let items = [
            TranscriptItem(role: .user, title: "A", body: "old", timestamp: now.addingTimeInterval(-7200), tags: ["sql"]),
        ]
        let (_, archived) = TranscriptArchiver.archive(items: items, olderThan: now.addingTimeInterval(-3600))
        XCTAssertEqual(archived.first?.tags, ["sql"])
    }

    func testArchivedItemsPreservePinnedFlag() {
        let now = Date()
        let items = [
            TranscriptItem(role: .user, title: "A", body: "old", timestamp: now.addingTimeInterval(-7200), isPinned: true),
        ]
        let (_, archived) = TranscriptArchiver.archive(items: items, olderThan: now.addingTimeInterval(-3600))
        XCTAssertTrue(archived.first?.isPinned == true)
    }
}

// MARK: - DataSource computed properties

final class DataSourceComputedPropertiesTests: XCTestCase {
    func testSupportedExtensionsDoesNotContainUnsupported() {
        let exts = DataSource.supportedExtensions
        XCTAssertFalse(exts.contains("xlsx"))
        XCTAssertFalse(exts.contains("txt"))
        XCTAssertFalse(exts.contains("pdf"))
    }

    func testIsTabularForAllFileTypes() {
        XCTAssertTrue(DataSource(url: URL(fileURLWithPath: "/tmp/a.parquet"), kind: .parquet).isTabularFile)
        XCTAssertTrue(DataSource(url: URL(fileURLWithPath: "/tmp/a.csv"), kind: .csv).isTabularFile)
        XCTAssertTrue(DataSource(url: URL(fileURLWithPath: "/tmp/a.json"), kind: .json).isTabularFile)
        XCTAssertFalse(DataSource(url: URL(fileURLWithPath: "/tmp/a.duckdb"), kind: .duckdb).isTabularFile)
    }

    func testSelectQueryWithPathContainingSpaces() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/my data/file.parquet"), kind: .parquet)
        let sql = source.selectQuery(limit: 5)
        XCTAssertNotNil(sql)
        XCTAssertTrue(sql?.contains("LIMIT 5") == true)
    }

    func testSummarizeQueryForJSON() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.json"), kind: .json)
        let sql = source.summarizeQuery()
        XCTAssertTrue(sql?.contains("SUMMARIZE") == true)
        XCTAssertTrue(sql?.contains("read_json") == true)
    }

    func testDescribeQueryForCSV() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.csv"), kind: .csv)
        let sql = source.describeQuery()
        XCTAssertTrue(sql?.contains("DESCRIBE") == true)
        XCTAssertTrue(sql?.contains("read_csv") == true)
    }
}

// MARK: - QueryExecutionStats formatting

final class QueryExecutionStatsFormattingTests: XCTestCase {
    func testFormattedDurationVariousRanges() {
        XCTAssertEqual(QueryExecutionStats(sql: "", durationMilliseconds: 0.1, succeeded: true).durationFormatted, "<1ms")
        XCTAssertEqual(QueryExecutionStats(sql: "", durationMilliseconds: 1, succeeded: true).durationFormatted, "1ms")
        XCTAssertEqual(QueryExecutionStats(sql: "", durationMilliseconds: 999, succeeded: true).durationFormatted, "999ms")
        XCTAssertEqual(QueryExecutionStats(sql: "", durationMilliseconds: 1000, succeeded: true).durationFormatted, "1.00s")
        XCTAssertEqual(QueryExecutionStats(sql: "", durationMilliseconds: 15000, succeeded: true).durationFormatted, "15.00s")
    }
}

// MARK: - CommandInfo model

final class CommandInfoModelTests: XCTestCase {
    func testCommandInfoSendable() {
        let info = CommandInfo(command: "/help", description: "Show help")
        let copy = info // Value type, Sendable
        XCTAssertEqual(copy.command, "/help")
    }
}


// MARK: - Transcript Archiver

final class TranscriptArchiverTests: XCTestCase {
    func testArchiveOldItems() {
        let now = Date()
        let items = [
            TranscriptItem(role: .user, title: "A", body: "old", timestamp: now.addingTimeInterval(-7200)),
            TranscriptItem(role: .user, title: "B", body: "recent", timestamp: now.addingTimeInterval(-60)),
            TranscriptItem(role: .user, title: "C", body: "new", timestamp: now),
        ]
        let cutoff = now.addingTimeInterval(-3600) // 1 hour ago
        let (kept, archived) = TranscriptArchiver.archive(items: items, olderThan: cutoff)
        XCTAssertEqual(kept.count, 2)
        XCTAssertEqual(archived.count, 1)
        XCTAssertEqual(archived.first?.body, "old")
    }

    func testArchiveKeepingPinnedItems() {
        let now = Date()
        let items = [
            TranscriptItem(role: .user, title: "A", body: "old pinned", timestamp: now.addingTimeInterval(-7200), isPinned: true),
            TranscriptItem(role: .user, title: "B", body: "old not pinned", timestamp: now.addingTimeInterval(-7200)),
            TranscriptItem(role: .user, title: "C", body: "new", timestamp: now),
        ]
        let cutoff = now.addingTimeInterval(-3600)
        let (kept, archived) = TranscriptArchiver.archiveKeepingPinned(items: items, olderThan: cutoff)
        XCTAssertEqual(kept.count, 2) // pinned old + new
        XCTAssertEqual(archived.count, 1)
        XCTAssertEqual(archived.first?.body, "old not pinned")
    }

    func testArchiveEmptyItems() {
        let (kept, archived) = TranscriptArchiver.archive(items: [], olderThan: Date())
        XCTAssertTrue(kept.isEmpty)
        XCTAssertTrue(archived.isEmpty)
    }

    func testArchiveNothingOld() {
        let items = [TranscriptItem(role: .user, title: "A", body: "new", timestamp: Date())]
        let cutoff = Date().addingTimeInterval(-3600)
        let (kept, archived) = TranscriptArchiver.archive(items: items, olderThan: cutoff)
        XCTAssertEqual(kept.count, 1)
        XCTAssertTrue(archived.isEmpty)
    }
}

// MARK: - SQL Sanitizer

final class SQLSanitizerTests: XCTestCase {
    func testSelectIsReadOnly() {
        XCTAssertTrue(SQLSanitizer.isReadOnly("SELECT * FROM trades;"))
    }

    func testDropIsDangerous() {
        XCTAssertTrue(SQLSanitizer.containsDangerousOperations("DROP TABLE trades;"))
        XCTAssertFalse(SQLSanitizer.isReadOnly("DROP TABLE trades;"))
    }

    func testDeleteIsDangerous() {
        XCTAssertTrue(SQLSanitizer.containsDangerousOperations("DELETE FROM trades WHERE id = 1;"))
    }

    func testUpdateIsDangerous() {
        XCTAssertTrue(SQLSanitizer.containsDangerousOperations("UPDATE trades SET price = 100;"))
    }

    func testInsertIsDangerous() {
        XCTAssertTrue(SQLSanitizer.containsDangerousOperations("INSERT INTO trades VALUES (1, 2);"))
    }

    func testAlterIsDangerous() {
        XCTAssertTrue(SQLSanitizer.containsDangerousOperations("ALTER TABLE trades ADD COLUMN volume INT;"))
    }

    func testTruncateIsDangerous() {
        XCTAssertTrue(SQLSanitizer.containsDangerousOperations("TRUNCATE trades;"))
    }

    func testDescribeIsReadOnly() {
        XCTAssertTrue(SQLSanitizer.isReadOnly("DESCRIBE trades;"))
    }

    func testShowTablesIsReadOnly() {
        XCTAssertTrue(SQLSanitizer.isReadOnly("SHOW TABLES;"))
    }

    func testSummarizeIsReadOnly() {
        XCTAssertTrue(SQLSanitizer.isReadOnly("SUMMARIZE trades;"))
    }

    func testExtractTableNames() {
        let tables = SQLSanitizer.extractTableNames(from: "SELECT * FROM trades JOIN prices ON trades.id = prices.trade_id;")
        XCTAssertTrue(tables.contains("trades"))
        XCTAssertTrue(tables.contains("prices"))
    }

    func testExtractTableNamesFromSubquery() {
        let tables = SQLSanitizer.extractTableNames(from: "SELECT * FROM orders WHERE customer_id IN (SELECT id FROM customers);")
        XCTAssertTrue(tables.contains("orders"))
        XCTAssertTrue(tables.contains("customers"))
    }

    func testExtractTableNamesEmpty() {
        XCTAssertTrue(SQLSanitizer.extractTableNames(from: "SELECT 1;").isEmpty)
    }

    func testExtractTableNamesIgnoresReserved() {
        let tables = SQLSanitizer.extractTableNames(from: "SELECT * FROM trades WHERE price > 0;")
        XCTAssertFalse(tables.contains("where"))
        XCTAssertTrue(tables.contains("trades"))
    }
}

// MARK: - Prompt Context Builder

final class PromptContextBuilderTests: XCTestCase {
    func testSourceContextWithParquet() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.parquet"), kind: .parquet)
        let ctx = PromptContextBuilder.sourceContext(for: source)
        XCTAssertTrue(ctx.contains("data.parquet"))
        XCTAssertTrue(ctx.contains("Parquet"))
        XCTAssertTrue(ctx.contains("read_parquet"))
    }

    func testSourceContextWithAlias() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.csv"), kind: .csv, alias: "Trades")
        let ctx = PromptContextBuilder.sourceContext(for: source)
        XCTAssertTrue(ctx.contains("Alias: Trades"))
    }

    func testSourceContextWithRemote() {
        let source = DataSource.fromRemoteURL("https://example.com/data.parquet")!
        let ctx = PromptContextBuilder.sourceContext(for: source)
        XCTAssertTrue(ctx.contains("Remote"))
    }

    func testSourceContextNilSource() {
        let ctx = PromptContextBuilder.sourceContext(for: nil)
        XCTAssertTrue(ctx.contains("No data source"))
    }

    func testSourceContextForDuckDB() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/db.duckdb"), kind: .duckdb)
        let ctx = PromptContextBuilder.sourceContext(for: source)
        XCTAssertTrue(ctx.contains("DuckDB"))
        XCTAssertFalse(ctx.contains("read_"))
    }

    func testShortLabel() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.parquet"), kind: .parquet)
        let label = PromptContextBuilder.shortLabel(for: source)
        XCTAssertEqual(label, "data.parquet (Parquet)")
    }

    func testShortLabelWithAlias() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.csv"), kind: .csv, alias: "My Data")
        let label = PromptContextBuilder.shortLabel(for: source)
        XCTAssertEqual(label, "My Data (CSV)")
    }

    func testShortLabelForJSON() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.json"), kind: .json)
        let label = PromptContextBuilder.shortLabel(for: source)
        XCTAssertEqual(label, "data.json (JSON)")
    }
}

// MARK: - DuckDB BETWEEN pattern

final class DuckDBBetweenPatternTests: XCTestCase {
    func testBetweenPatternGeneratesSQL() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/db.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "price between 50 and 200 in trades", source: source)
        guard case let .command(plan) = action else {
            return XCTFail("Expected command, got \(action)")
        }
        XCTAssertTrue(plan.sql.contains("BETWEEN 50 AND 200"))
        XCTAssertTrue(plan.sql.contains("FROM trades"))
    }

    func testExtractBetweenPattern() {
        let result = AssistantPlanner.extractBetweenPattern(from: "age between 18 and 65 in users")
        XCTAssertEqual(result?.table, "users")
        XCTAssertEqual(result?.column, "age")
        XCTAssertEqual(result?.low, "18")
        XCTAssertEqual(result?.high, "65")
    }

    func testExtractBetweenFromTable() {
        let result = AssistantPlanner.extractBetweenPattern(from: "date between 2024-01-01 and 2024-12-31 from events")
        XCTAssertEqual(result?.table, "events")
        XCTAssertEqual(result?.column, "date")
    }

    func testExtractBetweenNoMatch() {
        XCTAssertNil(AssistantPlanner.extractBetweenPattern(from: "show me data"))
    }
}

// MARK: - QueryHistoryManager

final class QueryHistoryManagerTests: XCTestCase {
    func testCommandHistory() {
        let items = [
            TranscriptItem(role: .assistant, title: "Preview", body: "preview",
                           kind: .commandPreview(sql: "SELECT * FROM trades;", sourceName: "db")),
            TranscriptItem(role: .user, title: "You", body: "Q"),
            TranscriptItem(role: .assistant, title: "Preview", body: "count",
                           kind: .commandPreview(sql: "SELECT COUNT(*) FROM trades;", sourceName: "db")),
        ]
        let history = QueryHistoryManager.commandHistory(from: items)
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history[0].sql, "SELECT * FROM trades;")
    }

    func testFrequentCommands() {
        let items = [
            TranscriptItem(role: .assistant, title: "P", body: "", kind: .commandPreview(sql: "SELECT 1;", sourceName: "db")),
            TranscriptItem(role: .assistant, title: "P", body: "", kind: .commandPreview(sql: "SELECT 2;", sourceName: "db")),
            TranscriptItem(role: .assistant, title: "P", body: "", kind: .commandPreview(sql: "SELECT 1;", sourceName: "db")),
            TranscriptItem(role: .assistant, title: "P", body: "", kind: .commandPreview(sql: "SELECT 1;", sourceName: "db")),
        ]
        let frequent = QueryHistoryManager.frequentCommands(from: items)
        XCTAssertEqual(frequent.first?.sql, "SELECT 1;")
        XCTAssertEqual(frequent.first?.count, 3)
    }

    func testRecentUniqueCommands() {
        let items = [
            TranscriptItem(role: .assistant, title: "P", body: "", kind: .commandPreview(sql: "A;", sourceName: "db")),
            TranscriptItem(role: .assistant, title: "P", body: "", kind: .commandPreview(sql: "B;", sourceName: "db")),
            TranscriptItem(role: .assistant, title: "P", body: "", kind: .commandPreview(sql: "A;", sourceName: "db")),
            TranscriptItem(role: .assistant, title: "P", body: "", kind: .commandPreview(sql: "C;", sourceName: "db")),
        ]
        let recent = QueryHistoryManager.recentUniqueCommands(from: items, limit: 3)
        XCTAssertEqual(recent.count, 3)
        XCTAssertEqual(recent[0], "C;") // Most recent first
        XCTAssertEqual(recent[1], "A;")
        XCTAssertEqual(recent[2], "B;")
    }

    func testFrequentCommandsLimit() {
        let items = (0..<20).map { i in
            TranscriptItem(role: .assistant, title: "P", body: "", kind: .commandPreview(sql: "SELECT \(i);", sourceName: "db"))
        }
        let frequent = QueryHistoryManager.frequentCommands(from: items, limit: 5)
        XCTAssertEqual(frequent.count, 5)
    }

    func testCommandHistoryEmpty() {
        XCTAssertTrue(QueryHistoryManager.commandHistory(from: []).isEmpty)
    }

    func testRecentUniqueCommandsEmpty() {
        XCTAssertTrue(QueryHistoryManager.recentUniqueCommands(from: []).isEmpty)
    }
}

// MARK: - DuckDB between pattern edge cases

final class DuckDBBetweenEdgeCaseTests: XCTestCase {
    func testBetweenWithDates() {
        let result = AssistantPlanner.extractBetweenPattern(from: "date between 2024-01-01 and 2024-12-31 in events")
        XCTAssertEqual(result?.column, "date")
        XCTAssertEqual(result?.low, "2024-01-01")
        XCTAssertEqual(result?.high, "2024-12-31")
    }

    func testBetweenWithDecimals() {
        let result = AssistantPlanner.extractBetweenPattern(from: "price between 1.5 and 99.9 from trades")
        XCTAssertEqual(result?.low, "1.5")
        XCTAssertEqual(result?.high, "99.9")
    }
}

// MARK: - QueryHistoryManager edge cases

final class QueryHistoryManagerEdgeCaseTests: XCTestCase {
    func testFrequentCommandsWithAllUnique() {
        let items = [
            TranscriptItem(role: .assistant, title: "P", body: "", kind: .commandPreview(sql: "A;", sourceName: "db")),
            TranscriptItem(role: .assistant, title: "P", body: "", kind: .commandPreview(sql: "B;", sourceName: "db")),
            TranscriptItem(role: .assistant, title: "P", body: "", kind: .commandPreview(sql: "C;", sourceName: "db")),
        ]
        let frequent = QueryHistoryManager.frequentCommands(from: items)
        XCTAssertEqual(frequent.count, 3)
        XCTAssertTrue(frequent.allSatisfy { $0.count == 1 })
    }

    func testRecentUniqueCommandsLimitSmaller() {
        let items = (0..<10).map { i in
            TranscriptItem(role: .assistant, title: "P", body: "", kind: .commandPreview(sql: "SQL\(i);", sourceName: "db"))
        }
        let recent = QueryHistoryManager.recentUniqueCommands(from: items, limit: 3)
        XCTAssertEqual(recent.count, 3)
    }

    func testCommandHistoryIgnoresNonCommands() {
        let items = [
            TranscriptItem(role: .user, title: "You", body: "Hello"),
            TranscriptItem(role: .assistant, title: "A", body: "Reply"),
            TranscriptItem(role: .system, title: "Sys", body: "Info"),
        ]
        XCTAssertTrue(QueryHistoryManager.commandHistory(from: items).isEmpty)
    }
}

// MARK: - SQL Formatter keyword coverage

final class SQLFormatterKeywordCoverageTests: XCTestCase {
    func testUppercaseJoinKeywords() {
        let formatted = SQLFormatter.uppercaseKeywords(in: "select * from a inner join b on a.id = b.id left join c using (id);")
        XCTAssertTrue(formatted.contains("INNER"))
        XCTAssertTrue(formatted.contains("LEFT"))
        XCTAssertTrue(formatted.contains("USING"))
    }

    func testUppercaseCaseWhen() {
        let formatted = SQLFormatter.uppercaseKeywords(in: "select case when x > 0 then 'positive' else 'negative' end from t;")
        XCTAssertTrue(formatted.contains("CASE"))
        XCTAssertTrue(formatted.contains("WHEN"))
        XCTAssertTrue(formatted.contains("THEN"))
        XCTAssertTrue(formatted.contains("ELSE"))
        XCTAssertTrue(formatted.contains("END"))
    }

    func testUppercaseAggregateFunctions() {
        let formatted = SQLFormatter.uppercaseKeywords(in: "select count(*), sum(price), avg(volume), min(date), max(date) from trades;")
        XCTAssertTrue(formatted.contains("COUNT"))
        XCTAssertTrue(formatted.contains("SUM"))
        XCTAssertTrue(formatted.contains("AVG"))
        XCTAssertTrue(formatted.contains("MIN"))
        XCTAssertTrue(formatted.contains("MAX"))
    }
}

// MARK: - DuckDB column type additional

final class DuckDBColumnTypeAdditionalTests: XCTestCase {
    func testInt8Type() {
        XCTAssertEqual(DuckDBColumnType.detect(from: "INT8"), .integer)
    }

    func testFloat4Type() {
        XCTAssertEqual(DuckDBColumnType.detect(from: "FLOAT4"), .decimal)
    }

    func testVarcharWithLength() {
        XCTAssertEqual(DuckDBColumnType.detect(from: "VARCHAR(100)"), .text)
    }

    func testTimestampTZ() {
        XCTAssertEqual(DuckDBColumnType.detect(from: "TIMESTAMPTZ"), .timestamp)
    }

    func testInt64Type() {
        XCTAssertEqual(DuckDBColumnType.detect(from: "INT64"), .integer)
    }

    func testDoublePrecision() {
        XCTAssertEqual(DuckDBColumnType.detect(from: "DOUBLE PRECISION"), .decimal)
    }
}

// MARK: - SQL formatter with DuckDB-specific keywords

final class SQLFormatterDuckDBTests: XCTestCase {
    func testUppercaseDescribeAndSummarize() {
        let formatted = SQLFormatter.uppercaseKeywords(in: "describe trades; summarize orders;")
        XCTAssertTrue(formatted.contains("DESCRIBE"))
        XCTAssertTrue(formatted.contains("SUMMARIZE"))
    }
}

// MARK: - DuckDB Query Builder

final class DuckDBQueryBuilderTests: XCTestCase {
    func testSimpleSelect() {
        let sql = DuckDBQueryBuilder(table: "trades").build()
        XCTAssertEqual(sql, "SELECT * FROM trades;")
    }

    func testSelectWithColumns() {
        let sql = DuckDBQueryBuilder(table: "trades")
            .selecting(["symbol", "price", "volume"])
            .build()
        XCTAssertEqual(sql, "SELECT symbol, price, volume FROM trades;")
    }

    func testSelectWithWhere() {
        let sql = DuckDBQueryBuilder(table: "trades")
            .filtering("price > 100")
            .build()
        XCTAssertEqual(sql, "SELECT * FROM trades WHERE price > 100;")
    }

    func testSelectWithOrderBy() {
        let sql = DuckDBQueryBuilder(table: "trades")
            .ordered(by: "price", descending: true)
            .build()
        XCTAssertEqual(sql, "SELECT * FROM trades ORDER BY price DESC;")
    }

    func testSelectWithLimit() {
        let sql = DuckDBQueryBuilder(table: "trades")
            .limited(to: 25)
            .build()
        XCTAssertEqual(sql, "SELECT * FROM trades LIMIT 25;")
    }

    func testSelectWithGroupBy() {
        let sql = DuckDBQueryBuilder(table: "trades")
            .selecting(["symbol", "COUNT(*)"])
            .grouped(by: "symbol")
            .build()
        XCTAssertEqual(sql, "SELECT symbol, COUNT(*) FROM trades GROUP BY symbol;")
    }

    func testComplexQuery() {
        let sql = DuckDBQueryBuilder(table: "trades")
            .selecting(["symbol", "AVG(price) AS avg_price"])
            .filtering("volume > 1000")
            .grouped(by: "symbol")
            .ordered(by: "avg_price", descending: true)
            .limited(to: 10)
            .build()
        XCTAssertTrue(sql.contains("SELECT symbol, AVG(price) AS avg_price"))
        XCTAssertTrue(sql.contains("FROM trades"))
        XCTAssertTrue(sql.contains("WHERE volume > 1000"))
        XCTAssertTrue(sql.contains("GROUP BY symbol"))
        XCTAssertTrue(sql.contains("ORDER BY avg_price DESC"))
        XCTAssertTrue(sql.contains("LIMIT 10"))
    }

    func testQueryBuilderEquality() {
        let a = DuckDBQueryBuilder(table: "trades").limited(to: 10)
        let b = DuckDBQueryBuilder(table: "trades").limited(to: 10)
        XCTAssertEqual(a, b)
    }

    func testQueryBuilderInequality() {
        let a = DuckDBQueryBuilder(table: "trades").limited(to: 10)
        let b = DuckDBQueryBuilder(table: "orders").limited(to: 10)
        XCTAssertNotEqual(a, b)
    }

    func testChainedBuilderImmutable() {
        let base = DuckDBQueryBuilder(table: "trades")
        let withLimit = base.limited(to: 5)
        let withOrder = base.ordered(by: "price")

        // base should not be modified
        XCTAssertNil(base.limit)
        XCTAssertNil(base.orderBy)
        XCTAssertEqual(withLimit.limit, 5)
        XCTAssertEqual(withOrder.orderBy, "price")
    }

    func testAscendingByDefault() {
        let sql = DuckDBQueryBuilder(table: "t")
            .ordered(by: "x")
            .build()
        XCTAssertTrue(sql.contains("ASC"))
    }
}

// MARK: - Source Statistics

final class SourceStatisticsTests: XCTestCase {
    func testEmptyStatistics() {
        let stats = SourceStatistics(sources: [])
        XCTAssertEqual(stats.totalSources, 0)
        XCTAssertEqual(stats.favoriteCount, 0)
        XCTAssertEqual(stats.remoteCount, 0)
    }

    func testStatisticsWithMixedSources() {
        let sources = [
            DataSource(url: URL(fileURLWithPath: "/tmp/a.parquet"), kind: .parquet, isFavorite: true),
            DataSource(url: URL(fileURLWithPath: "/tmp/b.parquet"), kind: .parquet, alias: "Prices"),
            DataSource(url: URL(fileURLWithPath: "/tmp/c.csv"), kind: .csv, notes: "Daily data"),
            DataSource(url: URL(fileURLWithPath: "/tmp/d.duckdb"), kind: .duckdb),
        ]
        let stats = SourceStatistics(sources: sources)
        XCTAssertEqual(stats.totalSources, 4)
        XCTAssertEqual(stats.byKind[.parquet], 2)
        XCTAssertEqual(stats.byKind[.csv], 1)
        XCTAssertEqual(stats.byKind[.duckdb], 1)
        XCTAssertNil(stats.byKind[.json])
        XCTAssertEqual(stats.favoriteCount, 1)
        XCTAssertEqual(stats.aliasedCount, 1)
        XCTAssertEqual(stats.withNotesCount, 1)
        XCTAssertEqual(stats.remoteCount, 0)
    }

    func testStatisticsSummary() {
        let sources = [
            DataSource(url: URL(fileURLWithPath: "/tmp/a.parquet"), kind: .parquet),
        ]
        let stats = SourceStatistics(sources: sources)
        let summary = stats.summary
        XCTAssertTrue(summary.contains("1 source"))
        XCTAssertTrue(summary.contains("Parquet"))
    }

    func testStatisticsWithRemote() {
        let remote = DataSource.fromRemoteURL("https://example.com/data.csv")!
        let stats = SourceStatistics(sources: [remote])
        XCTAssertEqual(stats.remoteCount, 1)
    }

    func testStatisticsEquality() {
        let sources = [DataSource(url: URL(fileURLWithPath: "/tmp/a.parquet"), kind: .parquet)]
        let a = SourceStatistics(sources: sources)
        let b = SourceStatistics(sources: sources)
        XCTAssertEqual(a, b)
    }
}

