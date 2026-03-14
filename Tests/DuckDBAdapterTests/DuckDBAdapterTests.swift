import XCTest
@testable import DuckDBAdapter
@testable import SiftCore

final class DuckDBAdapterTests: XCTestCase {
    func testBinaryLocatorPrefersEnvironmentOverride() {
        let candidates = DuckDBBinaryLocator.candidatePaths(environment: [
            "DUCKDB_BINARY": "/custom/duckdb",
            "PATH": "/bin:/usr/bin",
        ])

        XCTAssertEqual(candidates.first, "/custom/duckdb")
    }

    func testRequestForDuckDBUsesReadonlyDatabaseFile() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/market.duckdb"), kind: .duckdb)
        let plan = DuckDBCommandPlan(source: source, sql: "SHOW TABLES;", explanation: "Tables")

        let request = DuckDBCLIExecutor.request(for: plan, binaryPath: "/opt/homebrew/bin/duckdb")

        XCTAssertEqual(
            request.arguments,
            ["/tmp/market.duckdb", "-readonly", "-table", "-c", "SHOW TABLES;"]
        )
    }

    func testRequestForParquetUsesMemoryDatabase() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/prices.parquet"), kind: .parquet)
        let plan = DuckDBCommandPlan(source: source, sql: "SELECT * FROM read_parquet('/tmp/prices.parquet') LIMIT 25;", explanation: "Preview")

        let request = DuckDBCLIExecutor.request(for: plan, binaryPath: "/opt/homebrew/bin/duckdb")

        XCTAssertEqual(
            request.arguments,
            [":memory:", "-table", "-c", "SELECT * FROM read_parquet('/tmp/prices.parquet') LIMIT 25;"]
        )
    }

    func testRawArgumentParserHandlesQuotesAndEscapes() throws {
        let arguments = try DuckDBRawArgumentParser.parse(#""/tmp/market data.duckdb" -readonly -c "SHOW TABLES;""#)

        XCTAssertEqual(arguments, ["/tmp/market data.duckdb", "-readonly", "-c", "SHOW TABLES;"])
    }

    func testRequestForCSVUsesMemoryDatabase() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/trades.csv"), kind: .csv)
        let plan = DuckDBCommandPlan(source: source, sql: "SELECT * FROM read_csv('/tmp/trades.csv') LIMIT 25;", explanation: "Preview")

        let request = DuckDBCLIExecutor.request(for: plan, binaryPath: "/opt/homebrew/bin/duckdb")

        XCTAssertEqual(
            request.arguments,
            [":memory:", "-table", "-c", "SELECT * FROM read_csv('/tmp/trades.csv') LIMIT 25;"]
        )
    }

    func testRequestForJSONUsesMemoryDatabase() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.json"), kind: .json)
        let plan = DuckDBCommandPlan(source: source, sql: "SELECT * FROM read_json('/tmp/data.json') LIMIT 25;", explanation: "Preview")

        let request = DuckDBCLIExecutor.request(for: plan, binaryPath: "/opt/homebrew/bin/duckdb")

        XCTAssertEqual(
            request.arguments,
            [":memory:", "-table", "-c", "SELECT * FROM read_json('/tmp/data.json') LIMIT 25;"]
        )
    }

    func testRequestForRawArgumentsUsesExactArguments() {
        let request = DuckDBCLIExecutor.request(
            forRawArguments: ["--help"],
            binaryPath: "/opt/homebrew/bin/duckdb"
        )

        XCTAssertEqual(request.arguments, ["--help"])
        XCTAssertNil(request.source)
    }

    // MARK: - Binary locator

    func testBinaryLocatorPrefersExplicitOverPath() {
        let candidates = DuckDBBinaryLocator.candidatePaths(environment: [
            "DUCKDB_BINARY": "/custom/duckdb",
            "PATH": "/usr/bin:/bin",
        ])
        XCTAssertEqual(candidates.first, "/custom/duckdb")
        XCTAssertTrue(candidates.count > 1)
    }

    func testBinaryLocatorIncludesHomebrewAndUsrLocal() {
        let candidates = DuckDBBinaryLocator.candidatePaths(environment: [:])
        XCTAssertTrue(candidates.contains("/opt/homebrew/bin/duckdb"))
        XCTAssertTrue(candidates.contains("/usr/local/bin/duckdb"))
        XCTAssertTrue(candidates.contains("/usr/bin/duckdb"))
    }

    func testBinaryLocatorDeduplicates() {
        let candidates = DuckDBBinaryLocator.candidatePaths(environment: [
            "PATH": "/opt/homebrew/bin:/opt/homebrew/bin:/usr/bin",
        ])
        let homebrewCount = candidates.filter { $0 == "/opt/homebrew/bin/duckdb" }.count
        XCTAssertEqual(homebrewCount, 1)
    }

    func testBinaryLocatorEmptyPathStillHasFallbacks() {
        let candidates = DuckDBBinaryLocator.candidatePaths(environment: ["PATH": ""])
        XCTAssertFalse(candidates.isEmpty)
        XCTAssertTrue(candidates.contains("/opt/homebrew/bin/duckdb"))
    }

    // MARK: - Raw argument parser edge cases

    func testParserEmptyStringReturnsEmpty() throws {
        let args = try DuckDBRawArgumentParser.parse("")
        XCTAssertTrue(args.isEmpty)
    }

    func testParserWhitespaceOnlyReturnsEmpty() throws {
        let args = try DuckDBRawArgumentParser.parse("   \t  \n  ")
        XCTAssertTrue(args.isEmpty)
    }

    func testParserSingleQuotedString() throws {
        let args = try DuckDBRawArgumentParser.parse("'hello world'")
        XCTAssertEqual(args, ["hello world"])
    }

    func testParserDoubleQuotedString() throws {
        let args = try DuckDBRawArgumentParser.parse(#""hello world""#)
        XCTAssertEqual(args, ["hello world"])
    }

    func testParserEscapedSpaces() throws {
        let args = try DuckDBRawArgumentParser.parse(#"hello\ world"#)
        XCTAssertEqual(args, ["hello world"])
    }

    func testParserUnterminatedQuoteThrows() {
        XCTAssertThrowsError(try DuckDBRawArgumentParser.parse(#""unterminated"#)) { error in
            XCTAssertEqual(error as? DuckDBRawArgumentParser.Error, .unterminatedQuote)
        }
    }

    func testParserDanglingEscapeThrows() {
        XCTAssertThrowsError(try DuckDBRawArgumentParser.parse("hello\\")) { error in
            XCTAssertEqual(error as? DuckDBRawArgumentParser.Error, .danglingEscape)
        }
    }

    func testParserMixedArguments() throws {
        let args = try DuckDBRawArgumentParser.parse(#":memory: -c "SELECT 1;" -readonly"#)
        XCTAssertEqual(args, [":memory:", "-c", "SELECT 1;", "-readonly"])
    }

    func testParserBackslashInDoubleQuotes() throws {
        let args = try DuckDBRawArgumentParser.parse(#""hello\"world""#)
        XCTAssertEqual(args, [#"hello"world"#])
    }

    func testParserSingleQuotesPreserveBackslash() throws {
        let args = try DuckDBRawArgumentParser.parse(#"'hello\world'"#)
        XCTAssertEqual(args, [#"hello\world"#])
    }
}
