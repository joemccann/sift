import Foundation
import XCTest
@testable import SiftCore
@testable import SiftKit

final class SourceScannerTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sift-scanner-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testFindsParquetFiles() throws {
        let parquet = tempDir.appendingPathComponent("data.parquet")
        FileManager.default.createFile(atPath: parquet.path, contents: nil)

        let results = SourceScanner.scan(directory: tempDir)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.kind, .parquet)
        XCTAssertEqual(results.first?.url.standardizedFileURL, parquet.standardizedFileURL)
    }

    func testFindsDuckDBFiles() throws {
        let db = tempDir.appendingPathComponent("market.duckdb")
        FileManager.default.createFile(atPath: db.path, contents: nil)

        let results = SourceScanner.scan(directory: tempDir)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.kind, .duckdb)
    }

    func testFindsDBFiles() throws {
        let db = tempDir.appendingPathComponent("warehouse.db")
        FileManager.default.createFile(atPath: db.path, contents: nil)

        let results = SourceScanner.scan(directory: tempDir)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.kind, .duckdb)
    }

    func testIgnoresUnrelatedFiles() throws {
        let txt = tempDir.appendingPathComponent("readme.txt")
        let json = tempDir.appendingPathComponent("config.json")
        FileManager.default.createFile(atPath: txt.path, contents: nil)
        FileManager.default.createFile(atPath: json.path, contents: nil)

        let results = SourceScanner.scan(directory: tempDir)

        XCTAssertTrue(results.isEmpty)
    }

    func testScansSubdirectoriesRecursively() throws {
        let nested = tempDir.appendingPathComponent("warehouse/bronze/symbol=AAPL")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let parquet = nested.appendingPathComponent("data.parquet")
        FileManager.default.createFile(atPath: parquet.path, contents: nil)

        let topDB = tempDir.appendingPathComponent("market.duckdb")
        FileManager.default.createFile(atPath: topDB.path, contents: nil)

        let results = SourceScanner.scan(directory: tempDir)

        XCTAssertEqual(results.count, 2)
        let kinds = Set(results.map(\.kind))
        XCTAssertTrue(kinds.contains(.parquet))
        XCTAssertTrue(kinds.contains(.duckdb))
    }

    func testReturnsEmptyForNonexistentDirectory() {
        let missing = tempDir.appendingPathComponent("does-not-exist")

        let results = SourceScanner.scan(directory: missing)

        XCTAssertTrue(results.isEmpty)
    }

    func testResultsAreSortedByPath() throws {
        let a = tempDir.appendingPathComponent("aaa.parquet")
        let z = tempDir.appendingPathComponent("zzz.duckdb")
        let m = tempDir.appendingPathComponent("mmm.parquet")
        for file in [z, m, a] {
            FileManager.default.createFile(atPath: file.path, contents: nil)
        }

        let results = SourceScanner.scan(directory: tempDir)

        XCTAssertEqual(results.map(\.displayName), ["aaa.parquet", "mmm.parquet", "zzz.duckdb"])
    }
}
