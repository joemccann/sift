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

    func testSaveAndLoadWithAllTranscriptKinds() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = rootURL.appendingPathComponent("session.json")
        let store = AppSessionStore(fileURL: fileURL)

        let snapshot = AppSessionSnapshot(
            settings: AppSettings(hasCompletedSetup: true),
            sources: [],
            selectedSourceID: nil,
            transcript: [
                TranscriptItem(role: .assistant, title: "A", body: "text", kind: .text),
                TranscriptItem(role: .assistant, title: "A", body: "thinking", kind: .thinking),
                TranscriptItem(role: .assistant, title: "A", body: "preview",
                               kind: .commandPreview(sql: "SELECT 1;", sourceName: "test")),
                TranscriptItem(role: .assistant, title: "A", body: "raw",
                               kind: .rawCommandPreview(command: "--help")),
                TranscriptItem(role: .assistant, title: "A", body: "result",
                               kind: .commandResult(exitCode: 0, stdout: "ok", stderr: "")),
            ]
        )

        try store.saveSnapshot(snapshot)
        let restored = store.loadSnapshot()

        XCTAssertEqual(restored?.transcript.count, 5)
        XCTAssertEqual(restored?.transcript[0].kind, .text)
        XCTAssertEqual(restored?.transcript[1].kind, .thinking)
        XCTAssertEqual(restored?.transcript[2].kind, .commandPreview(sql: "SELECT 1;", sourceName: "test"))
        XCTAssertEqual(restored?.transcript[3].kind, .rawCommandPreview(command: "--help"))
        XCTAssertEqual(restored?.transcript[4].kind, .commandResult(exitCode: 0, stdout: "ok", stderr: ""))

        try? FileManager.default.removeItem(at: rootURL)
    }

    func testSaveAndLoadWithBookmarksAndTemplates() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = rootURL.appendingPathComponent("session.json")
        let store = AppSessionStore(fileURL: fileURL)

        var settings = AppSettings(hasCompletedSetup: true, preferredAppearance: .dark)
        settings.bookmarks = [BookmarkedCommand(sql: "SELECT 1;", sourceName: "test")]
        settings.queryTemplates = [QueryTemplate(name: "Count", sql: "SELECT COUNT(*);")]

        let snapshot = AppSessionSnapshot(
            settings: settings,
            sources: [DataSource(url: URL(fileURLWithPath: "/tmp/data.parquet"), kind: .parquet)],
            selectedSourceID: nil,
            transcript: []
        )

        try store.saveSnapshot(snapshot)
        let restored = store.loadSnapshot()

        XCTAssertEqual(restored?.settings.bookmarks.count, 1)
        XCTAssertEqual(restored?.settings.queryTemplates.count, 1)
        XCTAssertEqual(restored?.settings.preferredAppearance, .dark)
        XCTAssertEqual(restored?.sources.count, 1)

        try? FileManager.default.removeItem(at: rootURL)
    }

    func testSaveAndLoadWithPinnedItems() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = rootURL.appendingPathComponent("session.json")
        let store = AppSessionStore(fileURL: fileURL)

        let snapshot = AppSessionSnapshot(
            settings: AppSettings(hasCompletedSetup: true),
            sources: [],
            selectedSourceID: nil,
            transcript: [
                TranscriptItem(role: .assistant, title: "Important", body: "key result", isPinned: true),
                TranscriptItem(role: .user, title: "You", body: "question"),
            ]
        )

        try store.saveSnapshot(snapshot)
        let restored = store.loadSnapshot()

        XCTAssertTrue(restored?.transcript.first?.isPinned == true)
        XCTAssertFalse(restored?.transcript.last?.isPinned == true)

        try? FileManager.default.removeItem(at: rootURL)
    }
}
