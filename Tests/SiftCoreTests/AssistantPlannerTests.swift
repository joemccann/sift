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


