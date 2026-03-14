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
        panel.message = "Choose a local .duckdb, .db, .parquet, .csv, or .tsv file."
        panel.prompt = "Open"

        return panel.runModal() == .OK ? panel.url : nil
    }
}
