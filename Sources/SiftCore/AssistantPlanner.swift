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
    case rerunCommand(index: Int?)
    case showHistory
    case exportTranscript
    case showStatus
    case showVersion
    case showBookmarks
    case bookmarkLastCommand
    case undoLastMessage
    case showCommandCount
    case showSourceInfo
    case showPinnedItems
    case resetWorkspace
    case showTags
}

public struct CommandInfo: Equatable, Sendable {
    public let command: String
    public let description: String

    public init(command: String, description: String) {
        self.command = command
        self.description = description
    }
}

public enum CommandRegistry {
    public static let allCommands: [CommandInfo] = [
        CommandInfo(command: "/sql", description: "Run raw SQL against the active source"),
        CommandInfo(command: "/duckdb", description: "Run raw DuckDB CLI arguments"),
        CommandInfo(command: "/help", description: "Show available commands"),
        CommandInfo(command: "/clear", description: "Clear the conversation"),
        CommandInfo(command: "/sources", description: "List attached data sources"),
        CommandInfo(command: "/copy", description: "Copy last result to clipboard"),
        CommandInfo(command: "/rerun", description: "Re-execute the last command"),
        CommandInfo(command: "/history", description: "Show recent commands"),
        CommandInfo(command: "/export", description: "Export transcript as Markdown"),
        CommandInfo(command: "/status", description: "Show workspace status"),
        CommandInfo(command: "/version", description: "Show Sift version info"),
        CommandInfo(command: "/bookmark", description: "Bookmark the last command"),
        CommandInfo(command: "/bookmarks", description: "List saved bookmarks"),
        CommandInfo(command: "/undo", description: "Remove last user message"),
        CommandInfo(command: "/stats", description: "Show session statistics"),
        CommandInfo(command: "/info", description: "Show active source details"),
        CommandInfo(command: "/pins", description: "Show pinned items"),
        CommandInfo(command: "/reset", description: "Reset workspace (clear sources, bookmarks, transcript)"),
        CommandInfo(command: "/tags", description: "Show all tags used in the transcript"),
    ]

    /// Returns commands matching a prefix (for tab completion)
    public static func completions(for prefix: String) -> [CommandInfo] {
        let lowered = prefix.lowercased().trimmingCharacters(in: .whitespaces)
        guard lowered.hasPrefix("/"), lowered.count > 1 else {
            return lowered == "/" ? allCommands : []
        }
        return allCommands.filter { $0.command.lowercased().hasPrefix(lowered) }
    }
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
        case .json:
            return [
                PromptChip(title: "Preview rows", prompt: "Preview this JSON file"),
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

        if trimmed.caseInsensitiveCompare("/history") == .orderedSame {
            return .showHistory
        }

        if trimmed.caseInsensitiveCompare("/export") == .orderedSame {
            return .exportTranscript
        }

        if trimmed.caseInsensitiveCompare("/status") == .orderedSame {
            return .showStatus
        }

        if trimmed.caseInsensitiveCompare("/version") == .orderedSame {
            return .showVersion
        }

        if trimmed.caseInsensitiveCompare("/bookmarks") == .orderedSame {
            return .showBookmarks
        }

        if trimmed.caseInsensitiveCompare("/bookmark") == .orderedSame {
            return .bookmarkLastCommand
        }

        if trimmed.caseInsensitiveCompare("/undo") == .orderedSame {
            return .undoLastMessage
        }

        if trimmed.caseInsensitiveCompare("/stats") == .orderedSame {
            return .showCommandCount
        }

        if trimmed.caseInsensitiveCompare("/info") == .orderedSame {
            return .showSourceInfo
        }

        if trimmed.caseInsensitiveCompare("/pins") == .orderedSame || trimmed.caseInsensitiveCompare("/pinned") == .orderedSame {
            return .showPinnedItems
        }

        if trimmed.caseInsensitiveCompare("/reset") == .orderedSame {
            return .resetWorkspace
        }

        if trimmed.caseInsensitiveCompare("/tags") == .orderedSame {
            return .showTags
        }

        if trimmed.caseInsensitiveCompare("What can you do?") == .orderedSame || trimmed.caseInsensitiveCompare("/help") == .orderedSame {
            return .assistantReply(
                """
                **Sift Commands**

                • **Ask naturally** — "Give me the trading data for AAPL" → I'll generate SQL and run it
                • `/sql <query>` — Run raw SQL against the active source
                • `/duckdb <args>` — Run raw DuckDB CLI arguments
                • `/copy` — Copy the last query result to the clipboard
                • `/rerun` — Re-execute the last command (or `/rerun 2` for the 2nd-to-last)
                • `/history` — Show recent commands
                • `/export` — Copy full transcript to clipboard as Markdown
                • `/clear` — Clear the conversation transcript
                • `/sources` — List all attached data sources
                • `/bookmark` — Bookmark the last command for quick access
                • `/bookmarks` — List saved bookmarks
                • `/status` — Show workspace status summary
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

        if let rerunAction = parseRerun(from: trimmed) {
            return rerunAction
        }

        if trimmed.caseInsensitiveCompare("/sql") == .orderedSame {
            return .assistantReply("Use `/sql <query>` to run raw SQL against the active source. Example: `/sql SELECT * FROM my_table LIMIT 10;`")
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
        case .json:
            return planForJSON(prompt: trimmed, source: source)
        case .duckdb:
            return planForDuckDB(prompt: trimmed, source: source)
        }
    }

    private static func planForParquet(prompt: String, source: DataSource) -> AssistantAction {
        let escapedPath = escapeLiteral(source.path)
        let lowercased = prompt.lowercased()

        if lowercased.contains("parquet schema") || lowercased.contains("file schema") {
            return .command(
                DuckDBCommandPlan(
                    source: source,
                    sql: "SELECT * FROM parquet_schema('\(escapedPath)');",
                    explanation: "Reading parquet schema metadata from \(source.displayName)."
                )
            )
        }

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

        if lowercased.contains("metadata") || lowercased.contains("file info") {
            return .command(
                DuckDBCommandPlan(
                    source: source,
                    sql: "SELECT * FROM parquet_metadata('\(escapedPath)');",
                    explanation: "Reading parquet file metadata from \(source.displayName)."
                )
            )
        }

        if lowercased.contains("random") {
            return .command(
                DuckDBCommandPlan(
                    source: source,
                    sql: "SELECT * FROM read_parquet('\(escapedPath)') USING SAMPLE 10;",
                    explanation: "Randomly sampling 10 rows from \(source.displayName)."
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

        if lowercased.contains("random") {
            return .command(
                DuckDBCommandPlan(
                    source: source,
                    sql: "SELECT * FROM read_csv('\(escapedPath)') USING SAMPLE 10;",
                    explanation: "Randomly sampling 10 rows from \(source.displayName)."
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

    private static func planForJSON(prompt: String, source: DataSource) -> AssistantAction {
        let escapedPath = escapeLiteral(source.path)
        let lowercased = prompt.lowercased()

        if lowercased.contains("schema") {
            return .command(
                DuckDBCommandPlan(
                    source: source,
                    sql: "DESCRIBE SELECT * FROM read_json('\(escapedPath)');",
                    explanation: "Inspecting the JSON schema for \(source.displayName)."
                )
            )
        }

        if lowercased.contains("count") {
            return .command(
                DuckDBCommandPlan(
                    source: source,
                    sql: "SELECT COUNT(*) AS row_count FROM read_json('\(escapedPath)');",
                    explanation: "Counting rows in \(source.displayName)."
                )
            )
        }

        if lowercased.contains("summarize") || lowercased.contains("summary") || lowercased.contains("statistics") || lowercased.contains("stats") {
            return .command(
                DuckDBCommandPlan(
                    source: source,
                    sql: "SUMMARIZE SELECT * FROM read_json('\(escapedPath)');",
                    explanation: "Generating column statistics for \(source.displayName)."
                )
            )
        }

        if lowercased.contains("columns") || lowercased.contains("column names") || lowercased.contains("fields") {
            return .command(
                DuckDBCommandPlan(
                    source: source,
                    sql: "SELECT column_name, column_type FROM (DESCRIBE SELECT * FROM read_json('\(escapedPath)'));",
                    explanation: "Listing column names and types from \(source.displayName)."
                )
            )
        }

        if let limit = extractTopN(from: lowercased) {
            return .command(
                DuckDBCommandPlan(
                    source: source,
                    sql: "SELECT * FROM read_json('\(escapedPath)') LIMIT \(limit);",
                    explanation: "Showing top \(limit) rows from \(source.displayName)."
                )
            )
        }

        if lowercased.contains("random") {
            return .command(
                DuckDBCommandPlan(
                    source: source,
                    sql: "SELECT * FROM read_json('\(escapedPath)') USING SAMPLE 10;",
                    explanation: "Randomly sampling 10 rows from \(source.displayName)."
                )
            )
        }

        if lowercased.contains("preview") || lowercased.contains("show") || lowercased.contains("head") || lowercased.contains("first") || lowercased.contains("sample") {
            return .command(
                DuckDBCommandPlan(
                    source: source,
                    sql: "SELECT * FROM read_json('\(escapedPath)') LIMIT 25;",
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

        if lowercased.contains("show views") || lowercased.contains("list views") {
            return .command(
                DuckDBCommandPlan(
                    source: source,
                    sql: "SELECT view_name FROM duckdb_views() WHERE NOT internal;",
                    explanation: "Listing views in \(source.displayName)."
                )
            )
        }

        if lowercased.contains("show indexes") || lowercased.contains("list indexes") || lowercased.contains("show indices") {
            return .command(
                DuckDBCommandPlan(
                    source: source,
                    sql: "SELECT table_name, index_name, is_unique FROM duckdb_indexes();",
                    explanation: "Listing indexes in \(source.displayName)."
                )
            )
        }

        if lowercased.contains("version") && !looksLikeSQL(prompt) {
            return .command(
                DuckDBCommandPlan(
                    source: source,
                    sql: "PRAGMA version;",
                    explanation: "Checking DuckDB version for \(source.displayName)."
                )
            )
        }

        if let tableName = extractSummarizeTarget(from: lowercased) {
            return .command(
                DuckDBCommandPlan(
                    source: source,
                    sql: "SUMMARIZE \(tableName);",
                    explanation: "Generating column statistics for \(tableName) in \(source.displayName)."
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

        if lowercased.contains("memory") && (lowercased.contains("usage") || lowercased.contains("info")) {
            return .command(
                DuckDBCommandPlan(
                    source: source,
                    sql: "PRAGMA database_size;",
                    explanation: "Showing memory and storage info for \(source.displayName)."
                )
            )
        }

        if lowercased.contains("extensions") || lowercased.contains("installed extensions") {
            return .command(
                DuckDBCommandPlan(
                    source: source,
                    sql: "SELECT extension_name, installed, loaded FROM duckdb_extensions() WHERE installed;",
                    explanation: "Listing installed extensions for \(source.displayName)."
                )
            )
        }

        if lowercased.contains("settings") && !lowercased.contains("show") {
            return .command(
                DuckDBCommandPlan(
                    source: source,
                    sql: "SELECT name, value, description FROM duckdb_settings() LIMIT 25;",
                    explanation: "Showing DuckDB configuration settings for \(source.displayName)."
                )
            )
        }

        if let tableName = extractDescribeTarget(from: lowercased) {
            return .command(
                DuckDBCommandPlan(
                    source: source,
                    sql: "DESCRIBE \(tableName);",
                    explanation: "Describing the \(tableName) table in \(source.displayName)."
                )
            )
        }

        if let tableName = extractPreviewTarget(from: lowercased) {
            return .command(
                DuckDBCommandPlan(
                    source: source,
                    sql: "SELECT * FROM \(tableName) LIMIT 25;",
                    explanation: "Previewing rows from \(tableName) in \(source.displayName)."
                )
            )
        }

        if let tableName = extractCountTarget(from: lowercased) {
            return .command(
                DuckDBCommandPlan(
                    source: source,
                    sql: "SELECT COUNT(*) AS row_count FROM \(tableName);",
                    explanation: "Counting rows in \(tableName) from \(source.displayName)."
                )
            )
        }

        if let tableName = extractSampleTarget(from: lowercased) {
            return .command(
                DuckDBCommandPlan(
                    source: source,
                    sql: "SELECT * FROM \(tableName) USING SAMPLE 10;",
                    explanation: "Randomly sampling 10 rows from \(tableName) in \(source.displayName)."
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

        if let distinctInfo = extractDistinctPattern(from: lowercased) {
            return .command(
                DuckDBCommandPlan(
                    source: source,
                    sql: "SELECT DISTINCT \(distinctInfo.column) FROM \(distinctInfo.table) ORDER BY \(distinctInfo.column);",
                    explanation: "Unique values of \(distinctInfo.column) in \(distinctInfo.table) from \(source.displayName)."
                )
            )
        }

        if let groupInfo = extractGroupByPattern(from: lowercased) {
            return .command(
                DuckDBCommandPlan(
                    source: source,
                    sql: "SELECT \(groupInfo.column), COUNT(*) AS count FROM \(groupInfo.table) GROUP BY \(groupInfo.column) ORDER BY count DESC;",
                    explanation: "Counting rows by \(groupInfo.column) in \(groupInfo.table) from \(source.displayName)."
                )
            )
        }

        if let agg = extractAggregatePattern(from: lowercased) {
            return .command(
                DuckDBCommandPlan(
                    source: source,
                    sql: "SELECT \(agg.function)(\(agg.column)) AS result FROM \(agg.table);",
                    explanation: "\(agg.function.uppercased()) of \(agg.column) in \(agg.table) from \(source.displayName)."
                )
            )
        }

        if let orderInfo = extractOrderByPattern(from: lowercased) {
            return .command(
                DuckDBCommandPlan(
                    source: source,
                    sql: "SELECT * FROM \(orderInfo.table) ORDER BY \(orderInfo.column) \(orderInfo.descending ? "DESC" : "ASC") LIMIT 25;",
                    explanation: "Sorted by \(orderInfo.column) \(orderInfo.descending ? "descending" : "ascending") in \(orderInfo.table) from \(source.displayName)."
                )
            )
        }

        if !looksLikeSQL(prompt), let filter = extractWhereFilter(from: lowercased) {
            return .command(
                DuckDBCommandPlan(
                    source: source,
                    sql: "SELECT * FROM \(filter.table) WHERE \(filter.condition) LIMIT 25;",
                    explanation: "Filtering \(filter.table) where \(filter.condition) in \(source.displayName)."
                )
            )
        }

        if let joinInfo = extractJoinPattern(from: lowercased) {
            return .command(
                DuckDBCommandPlan(
                    source: source,
                    sql: "SELECT * FROM \(joinInfo.table1) JOIN \(joinInfo.table2) USING (\(joinInfo.column)) LIMIT 25;",
                    explanation: "Joining \(joinInfo.table1) and \(joinInfo.table2) on \(joinInfo.column) in \(source.displayName)."
                )
            )
        }

        if let topN = extractTopNByColumn(from: lowercased) {
            return .command(
                DuckDBCommandPlan(
                    source: source,
                    sql: "SELECT * FROM \(topN.table) ORDER BY \(topN.column) DESC LIMIT \(topN.limit);",
                    explanation: "Top \(topN.limit) rows from \(topN.table) ordered by \(topN.column) in \(source.displayName)."
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
        let keywords = ["select", "show", "describe", "pragma", "with", "from", "explain", "create", "insert", "update", "delete", "drop", "alter", "copy", "summarize"]
        let firstToken = prompt
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .first?
            .lowercased() ?? ""
        return keywords.contains(firstToken)
    }

    /// Extracts a table name from "summarize [table]" or "stats for [table]"
    static func extractSummarizeTarget(from lowercased: String) -> String? {
        let patterns = [
            "summarize (\\w+)",
            "summary of (\\w+)",
            "stats for (\\w+)",
            "statistics for (\\w+)",
        ]
        let reservedWords: Set<String> = [
            "the", "this", "data", "all", "my", "a", "it", "select",
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: lowercased, range: NSRange(lowercased.startIndex..., in: lowercased)),
               let nameRange = Range(match.range(at: 1), in: lowercased) {
                let name = String(lowercased[nameRange])
                if !reservedWords.contains(name), name.count > 1 {
                    return name
                }
            }
        }
        return nil
    }

    /// Extracts a table name from "sample [table]" or "random [table]"
    static func extractSampleTarget(from lowercased: String) -> String? {
        let patterns = [
            "sample (\\w+)",
            "random (\\w+)",
            "random rows from (\\w+)",
            "sample from (\\w+)",
        ]
        let reservedWords: Set<String> = [
            "the", "this", "rows", "all", "my", "a", "it", "data", "sample", "from",
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: lowercased, range: NSRange(lowercased.startIndex..., in: lowercased)),
               let nameRange = Range(match.range(at: 1), in: lowercased) {
                let name = String(lowercased[nameRange])
                if !reservedWords.contains(name), name.count > 1 {
                    return name
                }
            }
        }
        return nil
    }

    /// Extracts a table name from "count [table]" or "count rows in [table]"
    /// Extracts "avg/sum/min/max [column] in/from [table]" pattern
    static func extractAggregatePattern(from lowercased: String) -> (function: String, column: String, table: String)? {
        let pattern = "(avg|sum|min|max|average|total|minimum|maximum) (?:of )?(\\w+) (?:in|from|of) (\\w+)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: lowercased, range: NSRange(lowercased.startIndex..., in: lowercased)),
              match.numberOfRanges >= 4,
              let fnRange = Range(match.range(at: 1), in: lowercased),
              let colRange = Range(match.range(at: 2), in: lowercased),
              let tableRange = Range(match.range(at: 3), in: lowercased) else {
            return nil
        }

        let rawFn = String(lowercased[fnRange])
        let sqlFn: String
        switch rawFn {
        case "avg", "average": sqlFn = "AVG"
        case "sum", "total": sqlFn = "SUM"
        case "min", "minimum": sqlFn = "MIN"
        case "max", "maximum": sqlFn = "MAX"
        default: sqlFn = rawFn.uppercased()
        }

        return (function: sqlFn, column: String(lowercased[colRange]), table: String(lowercased[tableRange]))
    }

    /// Extracts "order by [column] in [table]" or "sort [table] by [column]"
    static func extractOrderByPattern(from lowercased: String) -> (table: String, column: String, descending: Bool)? {
        let patterns: [(pattern: String, tableGroup: Int, colGroup: Int)] = [
            ("(?:order|sort) (?:by )?(\\w+) (?:in|from) (\\w+)", 2, 1),
            ("sort (\\w+) by (\\w+)", 1, 2),
        ]

        for (pattern, tg, cg) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: lowercased, range: NSRange(lowercased.startIndex..., in: lowercased)),
               match.numberOfRanges >= 3,
               let tableRange = Range(match.range(at: tg), in: lowercased),
               let colRange = Range(match.range(at: cg), in: lowercased) {
                let desc = lowercased.contains("desc") || lowercased.contains("descending") || lowercased.contains("highest")
                return (table: String(lowercased[tableRange]), column: String(lowercased[colRange]), descending: desc)
            }
        }
        return nil
    }

    /// Extracts "distinct [column] in [table]" or "unique [column] from [table]"
    static func extractDistinctPattern(from lowercased: String) -> (table: String, column: String)? {
        let patterns = [
            "distinct (\\w+) (?:in|from) (\\w+)",
            "unique (\\w+) (?:in|from) (\\w+)",
            "unique values (?:of|in|for) (\\w+) (?:in|from) (\\w+)",
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: lowercased, range: NSRange(lowercased.startIndex..., in: lowercased)),
               match.numberOfRanges >= 3,
               let colRange = Range(match.range(at: 1), in: lowercased),
               let tableRange = Range(match.range(at: 2), in: lowercased) {
                return (table: String(lowercased[tableRange]), column: String(lowercased[colRange]))
            }
        }
        return nil
    }

    /// Extracts "group by [column] in [table]" or "count by [column] in [table]"
    static func extractGroupByPattern(from lowercased: String) -> (table: String, column: String)? {
        let patterns = [
            "group by (\\w+) (?:in|from) (\\w+)",
            "count by (\\w+) (?:in|from) (\\w+)",
            "breakdown by (\\w+) (?:in|from) (\\w+)",
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: lowercased, range: NSRange(lowercased.startIndex..., in: lowercased)),
               match.numberOfRanges >= 3,
               let colRange = Range(match.range(at: 1), in: lowercased),
               let tableRange = Range(match.range(at: 2), in: lowercased) {
                return (table: String(lowercased[tableRange]), column: String(lowercased[colRange]))
            }
        }
        return nil
    }

    /// Extracts "filter [table] where [condition]" or "where [condition] in [table]" pattern
    static func extractWhereFilter(from lowercased: String) -> (table: String, condition: String)? {
        let patterns = [
            "filter (\\w+) where (.+)",
            "show (\\w+) where (.+)",
            "from (\\w+) where (.+)",
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: lowercased, range: NSRange(lowercased.startIndex..., in: lowercased)),
               match.numberOfRanges >= 3,
               let tableRange = Range(match.range(at: 1), in: lowercased),
               let condRange = Range(match.range(at: 2), in: lowercased) {
                let table = String(lowercased[tableRange])
                let condition = String(lowercased[condRange]).trimmingCharacters(in: .whitespaces)
                if !condition.isEmpty {
                    return (table: table, condition: condition)
                }
            }
        }
        return nil
    }

    /// Extracts "join [table1] and [table2] on [column]" pattern
    static func extractJoinPattern(from lowercased: String) -> (table1: String, table2: String, column: String)? {
        let patterns = [
            "join (\\w+) and (\\w+) on (\\w+)",
            "join (\\w+) with (\\w+) on (\\w+)",
            "join (\\w+) and (\\w+) using (\\w+)",
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: lowercased, range: NSRange(lowercased.startIndex..., in: lowercased)),
               match.numberOfRanges >= 4,
               let t1Range = Range(match.range(at: 1), in: lowercased),
               let t2Range = Range(match.range(at: 2), in: lowercased),
               let colRange = Range(match.range(at: 3), in: lowercased) {
                return (
                    table1: String(lowercased[t1Range]),
                    table2: String(lowercased[t2Range]),
                    column: String(lowercased[colRange])
                )
            }
        }
        return nil
    }

    /// Extracts "top N by column from table" pattern
    static func extractTopNByColumn(from lowercased: String) -> (table: String, column: String, limit: Int)? {
        let patterns = [
            "top (\\d+) by (\\w+) (?:from|in) (\\w+)",
            "top (\\d+) (\\w+) (?:from|in) (\\w+)",
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: lowercased, range: NSRange(lowercased.startIndex..., in: lowercased)),
               match.numberOfRanges >= 4,
               let numRange = Range(match.range(at: 1), in: lowercased),
               let colRange = Range(match.range(at: 2), in: lowercased),
               let tableRange = Range(match.range(at: 3), in: lowercased),
               let num = Int(lowercased[numRange]),
               num > 0, num <= 10000 {
                return (table: String(lowercased[tableRange]), column: String(lowercased[colRange]), limit: num)
            }
        }
        return nil
    }

    static func extractCountTarget(from lowercased: String) -> String? {
        let patterns = [
            "count rows in (\\w+)",
            "count (\\w+) rows",
            "count (\\w+)",
        ]
        let reservedWords: Set<String> = [
            "the", "this", "rows", "all", "my", "a", "them", "it", "everything", "by",
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: lowercased, range: NSRange(lowercased.startIndex..., in: lowercased)),
               let nameRange = Range(match.range(at: 1), in: lowercased) {
                let name = String(lowercased[nameRange])
                if !reservedWords.contains(name), name.count > 1 {
                    return name
                }
            }
        }
        return nil
    }

    /// Extracts a table name from "preview [table]" or "show [table]"
    static func extractPreviewTarget(from lowercased: String) -> String? {
        let patterns = [
            "preview (\\w+)",
            "show (\\w+) rows",
            "head (\\w+)",
        ]
        let reservedWords: Set<String> = [
            "the", "this", "me", "a", "all", "my", "schema", "tables", "columns",
            "views", "indexes", "indices", "rows", "data", "info", "database",
            "settings", "extensions", "version", "memory", "installed",
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: lowercased, range: NSRange(lowercased.startIndex..., in: lowercased)),
               let nameRange = Range(match.range(at: 1), in: lowercased) {
                let name = String(lowercased[nameRange])
                if !reservedWords.contains(name), name.count > 1 {
                    return name
                }
            }
        }
        return nil
    }

    /// Extracts a table name from "describe [table]" or "describe the [table] table"
    static func extractDescribeTarget(from lowercased: String) -> String? {
        // Match "describe <tablename>" but not bare "describe" or "describe schema"
        let patterns = [
            "describe the (\\w+) table",
            "describe table (\\w+)",
            "describe (\\w+)",
        ]
        let reservedWords: Set<String> = ["the", "this", "schema", "database", "all", "it", "my", "a"]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: lowercased, range: NSRange(lowercased.startIndex..., in: lowercased)),
               let nameRange = Range(match.range(at: 1), in: lowercased) {
                let name = String(lowercased[nameRange])
                if !reservedWords.contains(name) {
                    return name
                }
            }
        }
        return nil
    }

    private static func parseRerun(from trimmed: String) -> AssistantAction? {
        let lowered = trimmed.lowercased()
        guard lowered.hasPrefix("/rerun") else { return nil }

        let rest = trimmed.dropFirst("/rerun".count).trimmingCharacters(in: .whitespacesAndNewlines)
        if rest.isEmpty {
            return .rerunCommand(index: nil)
        }
        if let n = Int(rest), n > 0 {
            return .rerunCommand(index: n)
        }
        return nil
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
