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

    func testParserAdjacentQuotedStrings() throws {
        let args = try DuckDBRawArgumentParser.parse(#"'hello'"world""#)
        XCTAssertEqual(args, ["helloworld"])
    }

    func testParserTabSeparated() throws {
        let args = try DuckDBRawArgumentParser.parse("a\tb\tc")
        XCTAssertEqual(args, ["a", "b", "c"])
    }

    func testParserNewlineSeparated() throws {
        let args = try DuckDBRawArgumentParser.parse("a\nb\nc")
        XCTAssertEqual(args, ["a", "b", "c"])
    }

    func testParserMultipleSpacesBetweenArgs() throws {
        let args = try DuckDBRawArgumentParser.parse("hello   world   foo")
        XCTAssertEqual(args, ["hello", "world", "foo"])
    }

    func testExecutionRequestSQLFieldIsSet() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/market.duckdb"), kind: .duckdb)
        let plan = DuckDBCommandPlan(source: source, sql: "SELECT 42;", explanation: "Test")
        let request = DuckDBCLIExecutor.request(for: plan, binaryPath: "/usr/bin/duckdb")
        XCTAssertEqual(request.sql, "SELECT 42;")
        XCTAssertEqual(request.source, source)
        XCTAssertEqual(request.binaryPath, "/usr/bin/duckdb")
    }

    func testExecutionRequestRawHasNilSource() {
        let request = DuckDBCLIExecutor.request(forRawArguments: ["-c", "SELECT 1;"], binaryPath: "/usr/bin/duckdb")
        XCTAssertNil(request.source)
        XCTAssertEqual(request.binaryPath, "/usr/bin/duckdb")
    }

    // MARK: - Execution request equatable

    func testExecutionRequestEquality() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/test.duckdb"), kind: .duckdb)
        let a = DuckDBExecutionRequest(binaryPath: "/usr/bin/duckdb", arguments: ["-c", "SELECT 1;"], sql: "SELECT 1;", source: source)
        let b = DuckDBExecutionRequest(binaryPath: "/usr/bin/duckdb", arguments: ["-c", "SELECT 1;"], sql: "SELECT 1;", source: source)
        XCTAssertEqual(a, b)
    }

    func testExecutionResultEquality() {
        let date = Date()
        let a = DuckDBExecutionResult(binaryPath: "/usr/bin/duckdb", arguments: [], sql: "SELECT 1;", stdout: "1", stderr: "", exitCode: 0, startedAt: date, endedAt: date)
        let b = DuckDBExecutionResult(binaryPath: "/usr/bin/duckdb", arguments: [], sql: "SELECT 1;", stdout: "1", stderr: "", exitCode: 0, startedAt: date, endedAt: date)
        XCTAssertEqual(a, b)
    }

    func testCLIErrorDescriptionForBinaryNotFound() {
        let error = DuckDBCLIError.binaryNotFound
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("duckdb"))
    }

    func testParserErrorDescriptions() {
        XCTAssertNotNil(DuckDBRawArgumentParser.Error.unterminatedQuote.errorDescription)
        XCTAssertNotNil(DuckDBRawArgumentParser.Error.danglingEscape.errorDescription)
    }

    func testBinaryLocatorWithMultiplePathSegments() {
        let candidates = DuckDBBinaryLocator.candidatePaths(environment: [
            "PATH": "/usr/bin:/usr/local/bin:/opt/homebrew/bin",
        ])
        // Should have at least 3 from PATH + 3 hardcoded (deduped)
        XCTAssertGreaterThanOrEqual(candidates.count, 3)
    }

    func testRequestSQLFieldForRawCommand() {
        let request = DuckDBCLIExecutor.request(forRawArguments: ["--version"], binaryPath: "/usr/bin/duckdb")
        XCTAssertEqual(request.sql, "--version")
    }

    // MARK: - Request building for all source kinds

    func testRequestForAllFileKindsUsesMemory() {
        for kind in [DataSourceKind.parquet, .csv, .json] {
            let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.\(kind.rawValue)"), kind: kind)
            let plan = DuckDBCommandPlan(source: source, sql: "SELECT 1;", explanation: "Test")
            let request = DuckDBCLIExecutor.request(for: plan, binaryPath: "/usr/bin/duckdb")
            XCTAssertEqual(request.arguments.first, ":memory:", "\(kind) should use :memory:")
        }
    }

    func testRequestForDuckDBUsesFilePath() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/db.duckdb"), kind: .duckdb)
        let plan = DuckDBCommandPlan(source: source, sql: "SHOW TABLES;", explanation: "Test")
        let request = DuckDBCLIExecutor.request(for: plan, binaryPath: "/usr/bin/duckdb")
        XCTAssertEqual(request.arguments.first, "/tmp/db.duckdb")
        XCTAssertTrue(request.arguments.contains("-readonly"))
    }

    func testRequestIncludesTableFlag() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.parquet"), kind: .parquet)
        let plan = DuckDBCommandPlan(source: source, sql: "SELECT 1;", explanation: "Test")
        let request = DuckDBCLIExecutor.request(for: plan, binaryPath: "/usr/bin/duckdb")
        XCTAssertTrue(request.arguments.contains("-table"))
        XCTAssertTrue(request.arguments.contains("-c"))
    }

    // MARK: - Binary locator priority

    func testBinaryLocatorExplicitAlwaysFirst() {
        let candidates = DuckDBBinaryLocator.candidatePaths(environment: [
            "DUCKDB_BINARY": "/my/custom/duckdb",
            "PATH": "/other/bin",
        ])
        XCTAssertEqual(candidates.first, "/my/custom/duckdb")
    }

    func testBinaryLocatorEmptyExplicitSkipped() {
        let candidates = DuckDBBinaryLocator.candidatePaths(environment: [
            "DUCKDB_BINARY": "",
            "PATH": "/usr/bin",
        ])
        // Empty DUCKDB_BINARY should be skipped
        XCTAssertFalse(candidates.first == "")
    }

    // MARK: - Request SQL content

    func testRequestForDuckDBContainsSQL() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/db.duckdb"), kind: .duckdb)
        let plan = DuckDBCommandPlan(source: source, sql: "SHOW TABLES;", explanation: "Test")
        let request = DuckDBCLIExecutor.request(for: plan, binaryPath: "/usr/bin/duckdb")
        XCTAssertTrue(request.arguments.contains("SHOW TABLES;"))
    }

    func testRequestForJSONContainsSQL() {
        let source = DataSource(url: URL(fileURLWithPath: "/tmp/data.json"), kind: .json)
        let sql = "SELECT * FROM read_json('/tmp/data.json') LIMIT 5;"
        let plan = DuckDBCommandPlan(source: source, sql: sql, explanation: "Test")
        let request = DuckDBCLIExecutor.request(for: plan, binaryPath: "/usr/bin/duckdb")
        XCTAssertEqual(request.sql, sql)
    }

    // MARK: - Parser compound cases

    func testParserComplexCommandLine() throws {
        let args = try DuckDBRawArgumentParser.parse(#"/tmp/db.duckdb -readonly -table -c "SELECT * FROM trades WHERE price > 100;""#)
        XCTAssertEqual(args.count, 5)
        XCTAssertEqual(args[0], "/tmp/db.duckdb")
        XCTAssertEqual(args[3], "-c")
        XCTAssertTrue(args[4].contains("SELECT"))
    }

    func testParserSingleArgument() throws {
        let args = try DuckDBRawArgumentParser.parse("--help")
        XCTAssertEqual(args, ["--help"])
    }

    // MARK: - CLI error equality

    func testCLIErrorLaunchFailedEquality() {
        XCTAssertEqual(DuckDBCLIError.launchFailed("x"), DuckDBCLIError.launchFailed("x"))
        XCTAssertNotEqual(DuckDBCLIError.launchFailed("x"), DuckDBCLIError.launchFailed("y"))
    }

    func testCLIErrorInvalidArgumentsEquality() {
        XCTAssertEqual(DuckDBCLIError.invalidArguments("a"), DuckDBCLIError.invalidArguments("a"))
        XCTAssertNotEqual(DuckDBCLIError.invalidArguments("a"), DuckDBCLIError.invalidArguments("b"))
    }

    // MARK: - Execution result

    func testExecutionResultExitCodes() {
        let date = Date()
        let success = DuckDBExecutionResult(binaryPath: "/usr/bin/duckdb", arguments: [], sql: "", stdout: "", stderr: "", exitCode: 0, startedAt: date, endedAt: date)
        let failure = DuckDBExecutionResult(binaryPath: "/usr/bin/duckdb", arguments: [], sql: "", stdout: "", stderr: "err", exitCode: 1, startedAt: date, endedAt: date)
        XCTAssertEqual(success.exitCode, 0)
        XCTAssertEqual(failure.exitCode, 1)
        XCTAssertNotEqual(success, failure)
    }
}
