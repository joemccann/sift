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
}
