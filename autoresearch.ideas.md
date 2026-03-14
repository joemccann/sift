# Autoresearch Ideas

## Deferred Feature Ideas
- Query cancellation — Task.cancel() on running DuckDB process, with tests for cancellation state
- Source drag-and-drop — UniformTypeIdentifiers + NSItemProvider, hard to unit test but could test the model layer
- Tab completion for commands — prefix matching on /help, /sql, /duckdb etc.
- Rate limiting / debounce for search — not critical for unit tests but good UX
- DuckDB EXPLAIN plan support — show query plan before executing
- Multiple concurrent sources — run queries across multiple sources
- Parquet metadata inspection — file-level metadata without full read
- Transcript pagination — for very long conversations
- Command bookmarking — save frequently used queries
- Source file watching — auto-refresh when source file changes
- Theme/appearance settings — dark/light mode preferences

## Completed Features
- Source removal (removeSource, removeAllSources)
- CSV/TSV file support
- /help command
- /clear, /sources, /copy, /rerun, /history, /export, /status, /version commands
- JSON/JSONL/NDJSON source support
- Conversation search
- Natural language → SQL query flow
- Thinking indicator
- Column listing for parquet/CSV/JSON
- Top-N extraction
- Random sampling (USING SAMPLE)
- DuckDB describe [tablename]
- DuckDB show views, indexes, version, memory, extensions, settings
- Path escaping for special characters
- Batch import
- Duplicate source prevention
- DataSourceKind computed properties
- Transcript role filtering
