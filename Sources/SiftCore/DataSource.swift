import Foundation

public enum DataSourceKind: String, CaseIterable, Codable, Sendable {
    case parquet
    case duckdb
    case csv
    case json
}

public struct DataSource: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let url: URL
    public let kind: DataSourceKind
    public let addedAt: Date

    public init(
        id: UUID = UUID(),
        url: URL,
        kind: DataSourceKind,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.url = url
        self.kind = kind
        self.addedAt = addedAt
    }

    public var displayName: String {
        url.lastPathComponent
    }

    public var path: String {
        url.path
    }

    public var fileSizeDescription: String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int64 else {
            return "unknown size"
        }

        if size < 1024 {
            return "\(size) B"
        } else if size < 1024 * 1024 {
            return "\(size / 1024) KB"
        } else if size < 1024 * 1024 * 1024 {
            return String(format: "%.1f MB", Double(size) / (1024 * 1024))
        } else {
            return String(format: "%.2f GB", Double(size) / (1024 * 1024 * 1024))
        }
    }

    public static func from(url: URL) -> DataSource? {
        switch url.pathExtension.lowercased() {
        case "parquet":
            DataSource(url: url, kind: .parquet)
        case "duckdb", "db":
            DataSource(url: url, kind: .duckdb)
        case "csv", "tsv":
            DataSource(url: url, kind: .csv)
        case "json", "jsonl", "ndjson":
            DataSource(url: url, kind: .json)
        default:
            nil
        }
    }
}
