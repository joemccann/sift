# Autoresearch Ideas

## Potential future features
- Provider response caching — in-memory LRU cache for recent responses
- Batch command execution — run multiple queries in sequence
- DuckDB ALTER TABLE patterns — rename/add column
- Query cost heuristic — estimate output size before running
- Source schema caching — cache DESCRIBE results for faster tab completion
- Result pagination — page through large query outputs
- Query diff — compare results of two queries side-by-side

## Completed (83 experiments, 916 tests)

### Slash commands (18)
/help, /clear, /sources, /copy, /rerun, /history, /export, /status, /version,
/bookmark, /bookmarks, /undo, /stats, /info, /pins, /tags, /reset, /sql

### File formats (4 kinds + remote)
Parquet, CSV/TSV, JSON/JSONL/NDJSON, DuckDB databases, HTTP/HTTPS URLs

### DuckDB patterns (14 extractors)
describe/preview/count/sample/summarize [table], top-N-by-column, join,
where filter, distinct, group-by, aggregate (avg/sum/min/max), order-by,
between, top-N rows

### Model types (20 new)
CommandRegistry, CommandAlias, BookmarkedCommand, QueryTemplate,
QueryExecutionStats, AppAppearance, SourceComparison, SourceStatistics,
DuckDBQueryBuilder, DuckDBColumnType, DuckDBOutputParser, DuckDBErrorRecovery,
QueryComplexityEstimator, SQLSanitizer, SQLFormatter, PromptContextBuilder,
MarkdownDetector, TranscriptAnalytics, TranscriptFilter, QueryHistoryManager

### Transcript system
Pinning, tagging, search+tag filter, compact mode, pagination, export
(Markdown/CSV/text), deduplication, archival, timing, analytics

### Source management
Removal, batch import, dedup prevention, favorites, aliases, notes,
file validation, comparison, grouping, search, remote URL import

### ViewModel capabilities
Cancellation, tab completion, execution stats, session export, contextual
suggestions, workspace reset, command aliases, SQL formatting/sanitization,
complexity estimation, query builder
