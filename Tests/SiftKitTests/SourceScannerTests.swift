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

    // MARK: - Depth limiting

    func testMaxDepthZeroFindsOnlyTopLevelFiles() throws {
        let topFile = tempDir.appendingPathComponent("top.parquet")
        FileManager.default.createFile(atPath: topFile.path, contents: nil)

        let nested = tempDir.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let nestedFile = nested.appendingPathComponent("nested.parquet")
        FileManager.default.createFile(atPath: nestedFile.path, contents: nil)

        let results = SourceScanner.scan(directory: tempDir, maxDepth: 0)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.displayName, "top.parquet")
    }

    func testMaxDepthOneFindsOneLevel() throws {
        // depth 0: root/
        // depth 1: root/sub/
        // depth 2: root/sub/deep/
        let sub = tempDir.appendingPathComponent("sub")
        let deep = sub.appendingPathComponent("deep")
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)

        FileManager.default.createFile(atPath: tempDir.appendingPathComponent("root.duckdb").path, contents: nil)
        FileManager.default.createFile(atPath: sub.appendingPathComponent("mid.parquet").path, contents: nil)
        FileManager.default.createFile(atPath: deep.appendingPathComponent("deep.parquet").path, contents: nil)

        let results = SourceScanner.scan(directory: tempDir, maxDepth: 1)

        XCTAssertEqual(results.count, 2)
        let names = Set(results.map(\.displayName))
        XCTAssertTrue(names.contains("root.duckdb"))
        XCTAssertTrue(names.contains("mid.parquet"))
        XCTAssertFalse(names.contains("deep.parquet"))
    }

    func testMaxDepthRespectsExactBoundary() throws {
        // 4 levels: root/a/b/c/d/
        var dir = tempDir!
        for name in ["a", "b", "c", "d"] {
            dir = dir.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: dir.appendingPathComponent("\(name).parquet").path, contents: nil)
        }

        let depth2 = SourceScanner.scan(directory: tempDir, maxDepth: 2)
        let depth2Names = Set(depth2.map(\.displayName))
        XCTAssertTrue(depth2Names.contains("a.parquet"))  // depth 1
        XCTAssertTrue(depth2Names.contains("b.parquet"))  // depth 2
        XCTAssertFalse(depth2Names.contains("c.parquet")) // depth 3 — excluded
        XCTAssertFalse(depth2Names.contains("d.parquet")) // depth 4 — excluded
    }

    func testDefaultDepthIsUnlimited() throws {
        // Existing tests pass without maxDepth, confirming default is unlimited
        var dir = tempDir!
        for name in ["l1", "l2", "l3", "l4", "l5"] {
            dir = dir.appendingPathComponent(name)
        }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: dir.appendingPathComponent("deep.parquet").path, contents: nil)

        let results = SourceScanner.scan(directory: tempDir)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.displayName, "deep.parquet")
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
