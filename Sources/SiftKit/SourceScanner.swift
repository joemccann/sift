import Foundation
import SiftCore

public enum SourceScanner {
    private static let supportedExtensions: Set<String> = ["parquet", "duckdb", "db"]

    public static func scan(
        directory: URL,
        fileManager: FileManager = .default
    ) -> [DataSource] {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var sources: [DataSource] = []
        for case let fileURL as URL in enumerator {
            let ext = fileURL.pathExtension.lowercased()
            guard supportedExtensions.contains(ext),
                  let source = DataSource.from(url: fileURL) else {
                continue
            }
            sources.append(source)
        }

        sources.sort { $0.url.path < $1.url.path }
        return sources
    }
}
