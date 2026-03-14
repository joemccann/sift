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

    // MARK: - Unsupported file types

    func testXLSXFileReturnsNil() {
        let source = DataSource.from(url: URL(fileURLWithPath: "/tmp/data.xlsx"))
        XCTAssertNil(source)
    }

    func testTXTFileReturnsNil() {
        let source = DataSource.from(url: URL(fileURLWithPath: "/tmp/data.txt"))
        XCTAssertNil(source)
    }
}
