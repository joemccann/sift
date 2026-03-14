# Autoresearch Ideas

## Promising Next Features
- Query cancellation — add `cancelRunningCommand()` with Task.cancel(), test isRunning state transitions
- Tab completion for commands — `commandCompletions(prefix:)` returning matching slash commands
- Transcript pagination — computed property for paginated transcript slices
- Source file watching — detect file modification timestamp changes  
- Theme/appearance settings — dark/light mode preference in AppSettings
- DuckDB table-specific preview — "preview trades" → `SELECT * FROM trades LIMIT 25;`
- Cross-source queries — query across multiple files with UNION
- Query template system — parameterized saved queries
- Transcript item pinning — pin important results
- Source metadata display — show file size, row count estimate on import

## Completed (prune from backlog)
- Source removal, CSV/TSV, /help, JSON/JSONL/NDJSON
- /clear, /sources, /copy, /rerun, /history, /export, /status, /version, /bookmark, /bookmarks, /undo, /stats
- Natural language → SQL, thinking indicator, conversation search
- Column listing, top-N, random sampling, parquet metadata/schema
- DuckDB describe [table], show views/indexes/version/memory/extensions/settings
- Path escaping, batch import, duplicate prevention
- DataSourceKind properties, transcript role filtering, source sorting
- Error handling for DuckDB unavailable, provider errors
- Bookmark persistence, command counting
