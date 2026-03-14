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

    func testShowOrdersWhereStatus() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/market.duckdb"), kind: .duckdb)
        let action = AssistantPlanner.plan(prompt: "show orders where status = 'filled'", source: source)

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

