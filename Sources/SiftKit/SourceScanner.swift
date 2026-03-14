import Foundation
import SiftCore

public enum SourceScanner {
    public static let defaultMaxDepth = 3
    private static let supportedExtensions: Set<String> = ["parquet", "duckdb", "db"]

    public static func scan(
        directory: URL,
        maxDepth: Int? = nil,
        fileManager: FileManager = .default
    ) -> [DataSource] {
        var sources: [DataSource] = []
        collect(directory: directory, currentDepth: 0, maxDepth: maxDepth, fileManager: fileManager, into: &sources)
        sources.sort { $0.url.path < $1.url.path }
        return sources
    }

    private static func collect(
        directory: URL,
        currentDepth: Int,
        maxDepth: Int?,
        fileManager: FileManager,
        into sources: inout [DataSource]
    ) {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for url in contents {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            if isDir {
                if maxDepth == nil || currentDepth < maxDepth! {
                    collect(directory: url, currentDepth: currentDepth + 1, maxDepth: maxDepth, fileManager: fileManager, into: &sources)
                }
            } else {
                let ext = url.pathExtension.lowercased()
                if supportedExtensions.contains(ext), let source = DataSource.from(url: url) {
                    sources.append(source)
                }
            }
        }
    }
}
