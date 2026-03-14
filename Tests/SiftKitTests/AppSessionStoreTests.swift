import Foundation
import XCTest
@testable import SiftCore
@testable import SiftKit

final class AppSessionStoreTests: XCTestCase {
    func testSaveAndLoadSnapshotRoundTrips() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = rootURL.appendingPathComponent("session.json")
        let store = AppSessionStore(fileURL: fileURL)

        let source = DataSource(url: URL(fileURLWithPath: "/tmp/prices.parquet"), kind: .parquet)
        let snapshot = AppSessionSnapshot(
            settings: AppSettings(hasCompletedSetup: true, defaultProvider: .gemini),
            sources: [source],
            selectedSourceID: source.id,
            transcript: [
                TranscriptItem(role: .assistant, title: "Saved", body: "Round trip")
            ]
        )

        try store.saveSnapshot(snapshot)
        let restored = store.loadSnapshot()

        XCTAssertEqual(restored, snapshot)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        try? FileManager.default.removeItem(at: rootURL)
    }

    func testLoadReturnsNilForMissingFile() {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("nonexistent.json")
        let store = AppSessionStore(fileURL: fileURL)

        XCTAssertNil(store.loadSnapshot())
    }

    func testLoadReturnsNilForCorruptFile() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = rootURL.appendingPathComponent("session.json")

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try "not valid json {{{".write(to: fileURL, atomically: true, encoding: .utf8)

        let store = AppSessionStore(fileURL: fileURL)
        XCTAssertNil(store.loadSnapshot())

        try? FileManager.default.removeItem(at: rootURL)
    }

    func testSaveCreatesIntermediateDirectories() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("deep")
            .appendingPathComponent("nested")
        let fileURL = rootURL.appendingPathComponent("session.json")
        let store = AppSessionStore(fileURL: fileURL)

        let snapshot = AppSessionSnapshot(
            settings: AppSettings(hasCompletedSetup: true),
            sources: [],
            selectedSourceID: nil,
            transcript: []
        )

        try store.saveSnapshot(snapshot)

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        let loaded = store.loadSnapshot()
        XCTAssertEqual(loaded?.settings.hasCompletedSetup, true)

        try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent().deletingLastPathComponent())
    }

    func testSaveOverwritesPreviousSnapshot() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = rootURL.appendingPathComponent("session.json")
        let store = AppSessionStore(fileURL: fileURL)

        let snapshot1 = AppSessionSnapshot(
            settings: AppSettings(hasCompletedSetup: false),
            sources: [],
            selectedSourceID: nil,
            transcript: []
        )
        try store.saveSnapshot(snapshot1)
        XCTAssertEqual(store.loadSnapshot()?.settings.hasCompletedSetup, false)

        let snapshot2 = AppSessionSnapshot(
            settings: AppSettings(hasCompletedSetup: true),
            sources: [],
            selectedSourceID: nil,
            transcript: [TranscriptItem(role: .assistant, title: "A", body: "updated")]
        )
        try store.saveSnapshot(snapshot2)
        XCTAssertEqual(store.loadSnapshot()?.settings.hasCompletedSetup, true)
        XCTAssertEqual(store.loadSnapshot()?.transcript.count, 1)

        try? FileManager.default.removeItem(at: rootURL)
    }
}
