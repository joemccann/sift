import AppKit
import Foundation

enum SourcePicker {
    @MainActor
    static func pickURL() -> URL? {
        if let automationPath = ProcessInfo.processInfo.environment["SIFT_AUTOMATION_PICK_SOURCE"],
           !automationPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: automationPath)
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = []
        panel.message = "Choose a local .duckdb, .db, or .parquet file."
        panel.prompt = "Open"

        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor
    static func pickDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a directory to scan for .duckdb, .db, and .parquet files."
        panel.prompt = "Scan"

        return panel.runModal() == .OK ? panel.url : nil
    }
}
