import Foundation

public enum DataSourceKind: String, CaseIterable, Codable, Sendable {
    case parquet
    case duckdb
    case csv
    case json

    /// The DuckDB read function for file-based sources
    public var readFunction: String? {
        switch self {
        case .parquet: return "read_parquet"
        case .csv: return "read_csv"
        case .json: return "read_json"
        case .duckdb: return nil
        }
    }

    /// Human-readable display name for this source kind
    public var displayLabel: String {
        switch self {
        case .parquet: return "Parquet"
        case .csv: return "CSV"
        case .json: return "JSON"
        case .duckdb: return "DuckDB"
        }
    }

    /// File extensions recognized for this kind
    public var fileExtensions: [String] {
        switch self {
        case .parquet: return ["parquet"]
        case .csv: return ["csv", "tsv"]
        case .json: return ["json", "jsonl", "ndjson"]
        case .duckdb: return ["duckdb", "db"]
        }
    }
}

public struct DataSource: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let url: URL
    public let kind: DataSourceKind
    public let addedAt: Date
    public var alias: String?

    public init(
        id: UUID = UUID(),
        url: URL,
        kind: DataSourceKind,
        addedAt: Date = Date(),
        alias: String? = nil
    ) {
        self.id = id
        self.url = url
        self.kind = kind
        self.addedAt = addedAt
        self.alias = alias
    }

    /// Returns the alias if set, otherwise the filename
    public var displayName: String {
        alias ?? url.lastPathComponent
    }

    public var path: String {
        url.path
    }

    /// Check if the source file exists on disk
    public var fileExists: Bool {
        FileManager.default.fileExists(atPath: path)
    }

    /// Check if the source file is readable
    public var isReadable: Bool {
        FileManager.default.isReadableFile(atPath: path)
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

    /// File extension of this source
    public var fileExtension: String {
        url.pathExtension.lowercased()
    }

    /// Parent directory name
    public var directoryName: String {
        url.deletingLastPathComponent().lastPathComponent
    }

    /// The DuckDB read expression for this source (e.g., "read_parquet('/path/to/file.parquet')")
    public var duckDBReadExpression: String? {
        guard let readFn = kind.readFunction else { return nil }
        let location = isRemote ? url.absoluteString : path
        let escaped = location.replacingOccurrences(of: "'", with: "''")
        return "\(readFn)('\(escaped)')"
    }

    /// Build a SELECT query for this source with optional limit
    public func selectQuery(columns: String = "*", limit: Int? = nil) -> String? {
        guard let readExpr = duckDBReadExpression else {
            // DuckDB database — would need a table name
            return nil
        }
        var sql = "SELECT \(columns) FROM \(readExpr)"
        if let limit {
            sql += " LIMIT \(limit)"
        }
        return sql + ";"
    }

    /// Build a COUNT query for this source
    public func countQuery() -> String? {
        guard let readExpr = duckDBReadExpression else { return nil }
        return "SELECT COUNT(*) AS row_count FROM \(readExpr);"
    }

    /// Build a SUMMARIZE query for this source
    public func summarizeQuery() -> String? {
        guard let readExpr = duckDBReadExpression else { return nil }
        return "SUMMARIZE SELECT * FROM \(readExpr);"
    }

    /// Build a DESCRIBE query for this source
    public func describeQuery() -> String? {
        guard let readExpr = duckDBReadExpression else {
            return "DESCRIBE;" // DuckDB database — describe the whole db
        }
        return "DESCRIBE SELECT * FROM \(readExpr);"
    }

    /// Check if this source represents a tabular file format (not a database)
    public var isTabularFile: Bool {
        kind != .duckdb
    }

    /// Whether this source is a remote URL
    public var isRemote: Bool {
        url.scheme == "http" || url.scheme == "https"
    }

    /// The supported file extensions for all source kinds
    public static var supportedExtensions: Set<String> {
        Set(DataSourceKind.allCases.flatMap(\.fileExtensions))
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

    /// Create a DataSource from a remote URL string (http/https)
    public static func fromRemoteURL(_ urlString: String) -> DataSource? {
        guard let url = URL(string: urlString),
              (url.scheme == "http" || url.scheme == "https") else {
            return nil
        }
        return from(url: url)
    }
}

// MARK: - DuckDB Output Parsing

public enum DuckDBOutputParser {
    /// Extract the row count from DuckDB output (looks for "N rows" patterns)
    public static func extractRowCount(from output: String) -> Int? {
        // DuckDB -table format ends with "N rows" or the output has N data lines
        let patterns = [
            "(\\d+) rows?\\b",
            "row_count\\s*\\n\\s*(\\d+)",
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
               let range = Range(match.range(at: 1), in: output),
               let count = Int(output[range]) {
                return count
            }
        }
        return nil
    }

    /// Count the number of data rows in tabular output (lines that aren't headers or separators)
    public static func countDataRows(in output: String) -> Int {
        let lines = output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Skip header row and separator lines (─── or ---)
        let dataLines = lines.filter { line in
            !line.allSatisfy { $0 == "─" || $0 == "-" || $0 == "+" || $0 == "|" || $0 == " " }
        }

        // First non-separator line is typically the header
        return max(0, dataLines.count - 1)
    }

    /// Detect if the output contains an error message
    public static func containsError(in output: String) -> Bool {
        let lowered = output.lowercased()
        return lowered.contains("error:") || lowered.contains("parse error") ||
               lowered.contains("syntax error") || lowered.contains("catalog error") ||
               lowered.contains("binder error") || lowered.contains("invalid")
    }
}
