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
    public var isFavorite: Bool
    public var notes: String?

    public init(
        id: UUID = UUID(),
        url: URL,
        kind: DataSourceKind,
        addedAt: Date = Date(),
        alias: String? = nil,
        isFavorite: Bool = false,
        notes: String? = nil
    ) {
        self.id = id
        self.url = url
        self.kind = kind
        self.addedAt = addedAt
        self.alias = alias
        self.isFavorite = isFavorite
        self.notes = notes
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

// MARK: - Source Comparison

public struct SourceComparison: Equatable, Sendable {
    public let source1Name: String
    public let source2Name: String
    public let sameKind: Bool
    public let sameDirectory: Bool
    public let sameExtension: Bool

    public init(source1: DataSource, source2: DataSource) {
        self.source1Name = source1.displayName
        self.source2Name = source2.displayName
        self.sameKind = source1.kind == source2.kind
        self.sameDirectory = source1.directoryName == source2.directoryName
        self.sameExtension = source1.fileExtension == source2.fileExtension
    }

    public var summary: String {
        var lines = ["\(source1Name) vs \(source2Name)"]
        lines.append("Same type: \(sameKind ? "✓" : "✗")")
        lines.append("Same directory: \(sameDirectory ? "✓" : "✗")")
        lines.append("Same extension: \(sameExtension ? "✓" : "✗")")
        return lines.joined(separator: "\n")
    }
}

// MARK: - DuckDB Query Builder

public struct DuckDBQueryBuilder: Equatable, Sendable {
    public var table: String
    public var columns: [String]
    public var whereClause: String?
    public var orderBy: String?
    public var descending: Bool
    public var limit: Int?
    public var groupBy: String?

    public init(table: String) {
        self.table = table
        self.columns = ["*"]
        self.descending = false
    }

    public func selecting(_ cols: [String]) -> DuckDBQueryBuilder {
        var copy = self
        copy.columns = cols
        return copy
    }

    public func filtering(_ condition: String) -> DuckDBQueryBuilder {
        var copy = self
        copy.whereClause = condition
        return copy
    }

    public func ordered(by column: String, descending: Bool = false) -> DuckDBQueryBuilder {
        var copy = self
        copy.orderBy = column
        copy.descending = descending
        return copy
    }

    public func limited(to count: Int) -> DuckDBQueryBuilder {
        var copy = self
        copy.limit = count
        return copy
    }

    public func grouped(by column: String) -> DuckDBQueryBuilder {
        var copy = self
        copy.groupBy = column
        return copy
    }

    public func build() -> String {
        var parts = ["SELECT \(columns.joined(separator: ", "))"]
        parts.append("FROM \(table)")
        if let whereClause { parts.append("WHERE \(whereClause)") }
        if let groupBy { parts.append("GROUP BY \(groupBy)") }
        if let orderBy { parts.append("ORDER BY \(orderBy) \(descending ? "DESC" : "ASC")") }
        if let limit { parts.append("LIMIT \(limit)") }
        return parts.joined(separator: " ") + ";"
    }
}

// MARK: - Source Statistics

public struct SourceStatistics: Equatable, Sendable {
    public let totalSources: Int
    public let byKind: [DataSourceKind: Int]
    public let favoriteCount: Int
    public let aliasedCount: Int
    public let withNotesCount: Int
    public let remoteCount: Int

    public init(sources: [DataSource]) {
        self.totalSources = sources.count
        self.byKind = Dictionary(grouping: sources, by: \.kind).mapValues(\.count)
        self.favoriteCount = sources.filter(\.isFavorite).count
        self.aliasedCount = sources.filter { $0.alias != nil }.count
        self.withNotesCount = sources.filter { $0.notes != nil && !($0.notes?.isEmpty ?? true) }.count
        self.remoteCount = sources.filter(\.isRemote).count
    }

    public var summary: String {
        var lines = ["\(totalSources) source\(totalSources == 1 ? "" : "s")"]
        for kind in DataSourceKind.allCases {
            if let count = byKind[kind], count > 0 {
                lines.append("  \(kind.displayLabel): \(count)")
            }
        }
        if favoriteCount > 0 { lines.append("  Favorites: \(favoriteCount)") }
        if remoteCount > 0 { lines.append("  Remote: \(remoteCount)") }
        return lines.joined(separator: "\n")
    }
}

// MARK: - SQL Formatter

public enum SQLFormatter {
    /// Add basic formatting to a SQL query (uppercase keywords)
    public static func uppercaseKeywords(in sql: String) -> String {
        let keywords = ["select", "from", "where", "join", "on", "and", "or", "not",
                       "group by", "order by", "having", "limit", "offset", "union",
                       "insert", "update", "delete", "create", "drop", "alter",
                       "as", "in", "between", "like", "is", "null", "distinct",
                       "count", "sum", "avg", "min", "max", "desc", "asc",
                       "inner", "left", "right", "outer", "cross", "using",
                       "with", "case", "when", "then", "else", "end",
                       "exists", "all", "any", "into", "values", "set",
                       "describe", "summarize", "explain", "pragma", "show"]
        var result = sql
        for keyword in keywords.sorted(by: { $0.count > $1.count }) {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: keyword))\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: keyword.uppercased())
            }
        }
        return result
    }

    /// Estimate the number of clauses in a SQL query
    public static func clauseCount(in sql: String) -> Int {
        let upper = sql.uppercased()
        let clauses = ["SELECT", "FROM", "WHERE", "GROUP BY", "HAVING", "ORDER BY", "LIMIT", "JOIN"]
        return clauses.filter { upper.contains($0) }.count
    }
}

// MARK: - SQL Sanitizer

public enum SQLSanitizer {
    /// Check if a SQL string contains potentially dangerous operations
    public static func containsDangerousOperations(_ sql: String) -> Bool {
        let upper = sql.uppercased()
        let dangerous = ["DROP ", "DELETE ", "TRUNCATE ", "ALTER ", "UPDATE ", "INSERT "]
        return dangerous.contains { upper.contains($0) }
    }

    /// Check if SQL is read-only (safe for readonly mode)
    public static func isReadOnly(_ sql: String) -> Bool {
        !containsDangerousOperations(sql)
    }

    /// Extract table names referenced in a SQL query (simple heuristic)
    public static func extractTableNames(from sql: String) -> [String] {
        let patterns = [
            "FROM\\s+(\\w+)",
            "JOIN\\s+(\\w+)",
            "INTO\\s+(\\w+)",
            "UPDATE\\s+(\\w+)",
            "TABLE\\s+(\\w+)",
        ]
        var tables = Set<String>()
        let reserved: Set<String> = ["select", "where", "and", "or", "not", "null", "true", "false", "as", "on", "in"]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let matches = regex.matches(in: sql, range: NSRange(sql.startIndex..., in: sql))
                for match in matches {
                    if let range = Range(match.range(at: 1), in: sql) {
                        let name = String(sql[range]).lowercased()
                        if !reserved.contains(name) {
                            tables.insert(name)
                        }
                    }
                }
            }
        }
        return Array(tables).sorted()
    }
}

// MARK: - Prompt Context Builder

public enum PromptContextBuilder {
    /// Build a context string describing the current source
    public static func sourceContext(for source: DataSource?) -> String {
        guard let source else { return "No data source is currently selected." }

        var lines = [
            "Source: \(source.displayName)",
            "Type: \(source.kind.displayLabel)",
            "Path: \(source.path)",
        ]

        if let readExpr = source.duckDBReadExpression {
            lines.append("DuckDB read: \(readExpr)")
        }

        if source.isRemote {
            lines.append("(Remote source)")
        }

        if let alias = source.alias {
            lines.append("Alias: \(alias)")
        }

        return lines.joined(separator: "\n")
    }

    /// Build a short label for display in the UI
    public static func shortLabel(for source: DataSource) -> String {
        let name = source.displayName
        let kind = source.kind.displayLabel
        return "\(name) (\(kind))"
    }
}

// MARK: - DuckDB Query Complexity

public enum QueryComplexityLevel: String, Sendable {
    case simple    // SELECT, COUNT, DESCRIBE
    case moderate  // JOIN, GROUP BY, subquery
    case complex   // multiple JOINs, window functions, CTEs

    public var displayLabel: String {
        switch self {
        case .simple: return "Simple"
        case .moderate: return "Moderate"
        case .complex: return "Complex"
        }
    }
}

public enum QueryComplexityEstimator {
    public static func estimate(_ sql: String) -> QueryComplexityLevel {
        let upper = sql.uppercased()
        var score = 0

        if upper.contains("JOIN") { score += 2 }
        if upper.contains("GROUP BY") { score += 1 }
        if upper.contains("HAVING") { score += 1 }
        if upper.contains("WINDOW") || upper.contains("OVER (") { score += 2 }
        if upper.contains("WITH ") && upper.contains(" AS (") { score += 2 } // CTE
        if upper.contains("UNION") { score += 1 }
        if upper.contains("INTERSECT") || upper.contains("EXCEPT") { score += 1 }
        if upper.components(separatedBy: "SELECT").count > 2 { score += 2 } // subquery

        if score >= 4 { return .complex }
        if score >= 1 { return .moderate }
        return .simple
    }
}

// MARK: - DuckDB Type Detection

public enum DuckDBColumnType: String, Sendable {
    case integer
    case decimal
    case text
    case boolean
    case timestamp
    case date
    case blob
    case other

    public static func detect(from typeString: String) -> DuckDBColumnType {
        let upper = typeString.uppercased()
        if upper.contains("INT") || upper == "BIGINT" || upper == "SMALLINT" || upper == "TINYINT" || upper == "HUGEINT" {
            return .integer
        }
        if upper.contains("FLOAT") || upper.contains("DOUBLE") || upper.contains("DECIMAL") || upper.contains("NUMERIC") || upper == "REAL" {
            return .decimal
        }
        if upper.contains("VARCHAR") || upper.contains("TEXT") || upper.contains("CHAR") || upper == "STRING" || upper == "UUID" {
            return .text
        }
        if upper == "BOOLEAN" || upper == "BOOL" {
            return .boolean
        }
        if upper.contains("TIMESTAMP") || upper.contains("DATETIME") {
            return .timestamp
        }
        if upper == "DATE" {
            return .date
        }
        if upper.contains("BLOB") || upper.contains("BYTEA") {
            return .blob
        }
        return .other
    }
}

// MARK: - DuckDB Error Recovery

public enum DuckDBErrorRecovery {
    /// Suggest recovery actions based on an error message
    public static func suggestions(for errorMessage: String) -> [String] {
        let lowered = errorMessage.lowercased()
        var suggestions: [String] = []

        if lowered.contains("table") && lowered.contains("not") && lowered.contains("exist") {
            suggestions.append("Run SHOW TABLES; to see available tables")
            suggestions.append("Check for typos in the table name")
        }

        if lowered.contains("column") && (lowered.contains("not found") || lowered.contains("not exist")) {
            suggestions.append("Run DESCRIBE tablename; to see available columns")
            suggestions.append("Check column name spelling and case")
        }

        if lowered.contains("syntax error") || lowered.contains("parse error") {
            suggestions.append("Check SQL syntax — missing semicolon, unmatched quotes, or keywords")
            suggestions.append("Try simplifying the query")
        }

        if lowered.contains("permission") || lowered.contains("access denied") {
            suggestions.append("Check file permissions on the source file")
            suggestions.append("Try opening the file with read-only mode")
        }

        if lowered.contains("out of memory") || lowered.contains("memory") {
            suggestions.append("Try adding LIMIT to reduce result size")
            suggestions.append("Use SUMMARIZE instead of SELECT * for large tables")
        }

        if lowered.contains("file") && lowered.contains("not found") {
            suggestions.append("Check that the file path exists")
            suggestions.append("Use /sources to verify attached sources")
        }

        if suggestions.isEmpty {
            suggestions.append("Try /help for available commands")
            suggestions.append("Check DuckDB documentation for the specific error")
        }

        return suggestions
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
