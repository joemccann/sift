import Foundation

public struct DuckDBCommandPlan: Equatable, Sendable {
    public let source: DataSource
    public let sql: String
    public let explanation: String

    public init(source: DataSource, sql: String, explanation: String) {
        self.source = source
        self.sql = sql
        self.explanation = explanation
    }
}

public enum AssistantAction: Equatable, Sendable {
    case assistantReply(String)
    case command(DuckDBCommandPlan)
    case providerPrompt(String)
    case naturalLanguageQuery(prompt: String, source: DataSource)
    case rawCommand(String)
    case clearConversation
    case listSources
    case copyLastResult
}

public enum PromptLibrary {
    public static func prompts(for source: DataSource?) -> [PromptChip] {
        guard let source else {
            return [
                PromptChip(title: "Open a parquet file", prompt: "How do I get started with a parquet file?"),
                PromptChip(title: "Open a DuckDB database", prompt: "How do I get started with a DuckDB database?"),
                PromptChip(title: "DuckDB CLI help", prompt: "/duckdb --help"),
                PromptChip(title: "What can you do?", prompt: "What can you do?"),
            ]
        }

        switch source.kind {
        case .parquet:
            return [
                PromptChip(title: "Preview rows", prompt: "Preview this parquet file"),
                PromptChip(title: "Show schema", prompt: "Show the schema"),
                PromptChip(title: "Count rows", prompt: "Count rows"),
                PromptChip(title: "DuckDB CLI help", prompt: "/duckdb --help"),
            ]
        case .csv:
            return [
                PromptChip(title: "Preview rows", prompt: "Preview this CSV file"),
                PromptChip(title: "Show schema", prompt: "Show the schema"),
                PromptChip(title: "Count rows", prompt: "Count rows"),
                PromptChip(title: "Summarize", prompt: "Summarize this data"),
            ]
        case .duckdb:
            return [
                PromptChip(title: "Show tables", prompt: "Show tables"),
                PromptChip(title: "Database info", prompt: "Show database info"),
                PromptChip(title: "Paste SQL", prompt: "/sql SELECT * FROM sqlite_master LIMIT 5;"),
                PromptChip(title: "DuckDB CLI help", prompt: "/duckdb --help"),
            ]
        }
    }
}

public enum AssistantPlanner {
    public static func plan(prompt: String, source: DataSource?) -> AssistantAction {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .assistantReply("Ask a question, paste SQL with `/sql ...`, or use one of the quick prompts.")
        }

        if trimmed.caseInsensitiveCompare("/clear") == .orderedSame {
            return .clearConversation
        }

        if trimmed.caseInsensitiveCompare("/sources") == .orderedSame {
            return .listSources
        }

        if trimmed.caseInsensitiveCompare("What can you do?") == .orderedSame || trimmed.caseInsensitiveCompare("/help") == .orderedSame {
            return .assistantReply(
                """
                **Sift Commands**

                • **Ask naturally** — "Give me the trading data for AAPL" → I'll generate SQL and run it
                • `/sql <query>` — Run raw SQL against the active source
                • `/duckdb <args>` — Run raw DuckDB CLI arguments
                • `/copy` — Copy the last query result to the clipboard
                • `/clear` — Clear the conversation transcript
                • `/sources` — List all attached data sources
                • `/help` — Show this help message

                **Quick Actions** (when a source is attached)
                • "Preview rows" / "Show schema" / "Count rows" / "Summarize"
                • "Show tables" / "Database info" (DuckDB sources)
                • "Unique values in [column]" / "Top N [column]"

                **Tips**
                • Open `.duckdb`, `.parquet`, or `.csv` files as sources
                • Any question with a source attached will auto-generate and execute SQL
                • Without a source, questions go to your configured AI provider
                """
            )
        }

        if trimmed.caseInsensitiveCompare("/copy") == .orderedSame {
            return .copyLastResult
        }

        if trimmed.caseInsensitiveCompare("/duckdb") == .orderedSame {
            return .assistantReply("Use `/duckdb ...` to run raw DuckDB CLI arguments exactly as you would in Terminal after the `duckdb` binary name. Example: `/duckdb --help`.")
        }

        if let rawCommand = rawDuckDBCommand(from: trimmed) {
            return .rawCommand(rawCommand)
        }

        guard let source else {
            if trimmed.localizedCaseInsensitiveContains("parquet") || trimmed.localizedCaseInsensitiveContains("duckdb") {
                return .assistantReply("Use the toolbar to open a `.parquet` or `.duckdb` source first, then I can run real DuckDB commands against it.")
            }

            if trimmed.localizedCaseInsensitiveContains("show tables") || trimmed.localizedCaseInsensitiveContains("preview this") {
                return .assistantReply("Open a local `.duckdb` or `.parquet` source first. After that you can ask for a preview, schema, row count, or paste raw SQL with `/sql ...`.")
            }

            return .providerPrompt(trimmed)
        }

        if let sql = rawSQL(from: trimmed) {
            return .command(
                DuckDBCommandPlan(
                    source: source,
                    sql: sql,
                    explanation: "Running your SQL directly against \(source.displayName)."
                )
            )
        }

        switch source.kind {
        case .parquet:
            return planForParquet(prompt: trimmed, source: source)
        case .csv:
            return planForCSV(prompt: trimmed, source: source)
        case .duckdb:
            return planForDuckDB(prompt: trimmed, source: source)
        }
    }

    private static func planForParquet(prompt: String, source: DataSource) -> AssistantAction {
        let escapedPath = escapeLiteral(source.path)
        let lowercased = prompt.lowercased()

        if lowercased.contains("schema") {
            return .command(
                DuckDBCommandPlan(
                    source: source,
                    sql: "DESCRIBE SELECT * FROM read_parquet('\(escapedPath)');",
                    explanation: "Inspecting the parquet schema for \(source.displayName)."
                )
            )
        }

        if lowercased.contains("count") {
            return .command(
                DuckDBCommandPlan(
                    source: source,
                    sql: "SELECT COUNT(*) AS row_count FROM read_parquet('\(escapedPath)');",
                    explanation: "Counting rows in \(source.displayName)."
                )
            )
        }

        if lowercased.contains("summarize") || lowercased.contains("summary") || lowercased.contains("statistics") || lowercased.contains("stats") {
            return .command(
                DuckDBCommandPlan(
                    source: source,
                    sql: "SUMMARIZE SELECT * FROM read_parquet('\(escapedPath)');",
                    explanation: "Generating column statistics for \(source.displayName)."
                )
            )
        }

        if lowercased.contains("columns") || lowercased.contains("column names") || lowercased.contains("fields") {
            return .command(
                DuckDBCommandPlan(
                    source: source,
                    sql: "SELECT column_name, column_type FROM (DESCRIBE SELECT * FROM read_parquet('\(escapedPath)'));",
                    explanation: "Listing column names and types from \(source.displayName)."
                )
            )
        }

        if let limit = extractTopN(from: lowercased) {
            return .command(
                DuckDBCommandPlan(
                    source: source,
                    sql: "SELECT * FROM read_parquet('\(escapedPath)') LIMIT \(limit);",
                    explanation: "Showing top \(limit) rows from \(source.displayName)."
                )
            )
        }

        if lowercased.contains("preview") || lowercased.contains("show") || lowercased.contains("head") || lowercased.contains("first") || lowercased.contains("sample") {
            return .command(
                DuckDBCommandPlan(
                    source: source,
                    sql: "SELECT * FROM read_parquet('\(escapedPath)') LIMIT 25;",
                    explanation: "Previewing up to 25 rows from \(source.displayName)."
                )
            )
        }

        // Natural language query — ask the provider to generate SQL
        return .naturalLanguageQuery(prompt: prompt, source: source)
    }

    private static func planForCSV(prompt: String, source: DataSource) -> AssistantAction {
        let escapedPath = escapeLiteral(source.path)
        let lowercased = prompt.lowercased()

        if lowercased.contains("schema") {
            return .command(
                DuckDBCommandPlan(
                    source: source,
                    sql: "DESCRIBE SELECT * FROM read_csv('\(escapedPath)');",
                    explanation: "Inspecting the CSV schema for \(source.displayName)."
                )
            )
        }

        if lowercased.contains("count") {
            return .command(
                DuckDBCommandPlan(
                    source: source,
                    sql: "SELECT COUNT(*) AS row_count FROM read_csv('\(escapedPath)');",
                    explanation: "Counting rows in \(source.displayName)."
                )
            )
        }

        if lowercased.contains("summarize") || lowercased.contains("summary") || lowercased.contains("statistics") || lowercased.contains("stats") {
            return .command(
                DuckDBCommandPlan(
                    source: source,
                    sql: "SUMMARIZE SELECT * FROM read_csv('\(escapedPath)');",
                    explanation: "Generating column statistics for \(source.displayName)."
                )
            )
        }

        if lowercased.contains("columns") || lowercased.contains("column names") || lowercased.contains("fields") {
            return .command(
                DuckDBCommandPlan(
                    source: source,
                    sql: "SELECT column_name, column_type FROM (DESCRIBE SELECT * FROM read_csv('\(escapedPath)'));",
                    explanation: "Listing column names and types from \(source.displayName)."
                )
            )
        }

        if let limit = extractTopN(from: lowercased) {
            return .command(
                DuckDBCommandPlan(
                    source: source,
                    sql: "SELECT * FROM read_csv('\(escapedPath)') LIMIT \(limit);",
                    explanation: "Showing top \(limit) rows from \(source.displayName)."
                )
            )
        }

        if lowercased.contains("preview") || lowercased.contains("show") || lowercased.contains("head") || lowercased.contains("first") || lowercased.contains("sample") {
            return .command(
                DuckDBCommandPlan(
                    source: source,
                    sql: "SELECT * FROM read_csv('\(escapedPath)') LIMIT 25;",
                    explanation: "Previewing up to 25 rows from \(source.displayName)."
                )
            )
        }

        return .naturalLanguageQuery(prompt: prompt, source: source)
    }

    private static func planForDuckDB(prompt: String, source: DataSource) -> AssistantAction {
        let lowercased = prompt.lowercased()

        if lowercased.contains("database info") || lowercased.contains("database size") {
            return .command(
                DuckDBCommandPlan(
                    source: source,
                    sql: "PRAGMA database_list;",
                    explanation: "Showing attached database information for \(source.displayName)."
                )
            )
        }

        if lowercased.contains("show tables") || lowercased.contains("list tables") {
            return .command(
                DuckDBCommandPlan(
                    source: source,
                    sql: "SHOW TABLES;",
                    explanation: "Listing tables in \(source.displayName)."
                )
            )
        }

        if lowercased.contains("show columns") || lowercased.contains("list columns") || lowercased.contains("column names") {
            return .command(
                DuckDBCommandPlan(
                    source: source,
                    sql: "SELECT table_name, column_name, data_type FROM information_schema.columns ORDER BY table_name, ordinal_position;",
                    explanation: "Listing all columns across all tables in \(source.displayName)."
                )
            )
        }

        if lowercased.contains("table size") || lowercased.contains("row counts") {
            return .command(
                DuckDBCommandPlan(
                    source: source,
                    sql: "SELECT table_name, estimated_size, column_count, index_count FROM duckdb_tables();",
                    explanation: "Showing table sizes and metadata for \(source.displayName)."
                )
            )
        }

        if lowercased.contains("summarize") || lowercased.contains("summary") || lowercased.contains("statistics") || lowercased.contains("stats") {
            return .command(
                DuckDBCommandPlan(
                    source: source,
                    sql: "SUMMARIZE SELECT * FROM (SHOW TABLES);",
                    explanation: "Generating summary statistics for \(source.displayName)."
                )
            )
        }

        if lowercased.contains("describe") || lowercased.contains("schema") {
            return .command(
                DuckDBCommandPlan(
                    source: source,
                    sql: "DESCRIBE;",
                    explanation: "Describing the schema of \(source.displayName)."
                )
            )
        }

        if looksLikeSQL(prompt) {
            return .command(
                DuckDBCommandPlan(
                    source: source,
                    sql: prompt,
                    explanation: "Running your SQL directly against \(source.displayName)."
                )
            )
        }

        // Natural language query — ask the provider to generate SQL
        return .naturalLanguageQuery(prompt: prompt, source: source)
    }

    private static func rawSQL(from prompt: String) -> String? {
        let prefix = "/sql "
        guard prompt.lowercased().hasPrefix(prefix) else {
            return nil
        }

        return String(prompt.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func rawDuckDBCommand(from prompt: String) -> String? {
        let prefix = "/duckdb "
        guard prompt.lowercased().hasPrefix(prefix) else {
            return nil
        }

        return String(prompt.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func looksLikeSQL(_ prompt: String) -> Bool {
        let keywords = ["select", "show", "describe", "pragma", "with", "from"]
        let firstToken = prompt
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .first?
            .lowercased() ?? ""
        return keywords.contains(firstToken)
    }

    /// Extracts a numeric limit from patterns like "top 10", "first 5 rows", "show 100 rows"
    static func extractTopN(from lowercased: String) -> Int? {
        let patterns = [
            "top (\\d+)",
            "first (\\d+)",
            "last (\\d+)",
            "show (\\d+) rows",
            "show (\\d+) records",
            "limit (\\d+)",
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: lowercased, range: NSRange(lowercased.startIndex..., in: lowercased)),
               let numRange = Range(match.range(at: 1), in: lowercased),
               let num = Int(lowercased[numRange]),
               num > 0, num <= 10000 {
                return num
            }
        }
        return nil
    }

    private static func escapeLiteral(_ path: String) -> String {
        path.replacingOccurrences(of: "'", with: "''")
    }
}
