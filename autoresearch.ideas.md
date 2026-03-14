# Autoresearch Ideas

## Deferred Feature Ideas
- Query cancellation — Task.cancel() on running DuckDB process, with tests for cancellation state
- Source drag-and-drop — UniformTypeIdentifiers + NSItemProvider, hard to unit test but could test the model layer
- Transcript export — export full conversation as markdown
- Tab completion for commands — prefix matching on /help, /sql, /duckdb etc.
- Rate limiting / debounce for search — not critical for unit tests but good UX
- DuckDB EXPLAIN plan support — show query plan before executing
- Multiple concurrent sources — run queries across multiple sources
- Parquet metadata inspection — file-level metadata without full read
