import Foundation
import XCTest
@testable import SiftCore

final class SQLExtractorTests: XCTestCase {
    func testExtractsFencedSQLBlock() {
        let text = """
        Here's a query:

        ```sql
        SELECT * FROM market LIMIT 10;
        ```

        That should show the first rows.
        """

        let blocks = SQLExtractor.extract(from: text)

        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks.first, "SELECT * FROM market LIMIT 10;")
    }

    func testExtractsMultipleSQLBlocks() {
        let text = """
        First run:

        ```sql
        SHOW TABLES;
        ```

        Then:

        ```sql
        DESCRIBE market;
        ```
        """

        let blocks = SQLExtractor.extract(from: text)

        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0], "SHOW TABLES;")
        XCTAssertEqual(blocks[1], "DESCRIBE market;")
    }

    func testIgnoresNonSQLCodeBlocks() {
        let text = """
        Some python:

        ```python
        print("hello")
        ```

        And plain text.
        """

        let blocks = SQLExtractor.extract(from: text)

        XCTAssertTrue(blocks.isEmpty)
    }

    func testHandlesNoCodeBlocks() {
        let text = "Just a plain text response with no code blocks."

        let blocks = SQLExtractor.extract(from: text)

        XCTAssertTrue(blocks.isEmpty)
    }

    func testTrimsWhitespace() {
        let text = """
        ```sql
          SELECT count(*) FROM prices;
        ```
        """

        let blocks = SQLExtractor.extract(from: text)

        XCTAssertEqual(blocks.first, "SELECT count(*) FROM prices;")
    }

    func testHandlesMultilineSQLBlocks() {
        let text = """
        ```sql
        SELECT symbol, date, close
        FROM market
        WHERE symbol = 'AAPL'
        ORDER BY date DESC
        LIMIT 7;
        ```
        """

        let blocks = SQLExtractor.extract(from: text)

        XCTAssertEqual(blocks.count, 1)
        XCTAssertTrue(blocks.first!.contains("SELECT symbol, date, close"))
        XCTAssertTrue(blocks.first!.contains("LIMIT 7;"))
    }

    func testExtractsFirstBlockOnly() {
        let text = """
        ```sql
        SHOW TABLES;
        ```

        ```sql
        SELECT * FROM market;
        ```
        """

        let first = SQLExtractor.extractFirst(from: text)

        XCTAssertEqual(first, "SHOW TABLES;")
    }

    func testExtractsFirstReturnsNilWhenNone() {
        let text = "No SQL here."

        let first = SQLExtractor.extractFirst(from: text)

        XCTAssertNil(first)
    }
}
