# Autoresearch Ideas

## Promising Next Features
- Provider response caching — in-memory LRU cache
- Batch command execution — run multiple queries in sequence
- SQL formatting — pretty-print SQL queries
- DuckDB "rename [table]" — ALTER TABLE pattern
- Source import history — track when sources were last queried
- Query cost heuristic — estimate output size before running
- Transcript archival — archive old transcript items

## Completed (75 experiments, 822 tests)
All prior features plus: SQLSanitizer (dangerous ops, read-only, table extraction),
PromptContextBuilder (source context, labels), QueryComplexityEstimator,
DuckDBColumnType, TranscriptExporter/Deduplicator, CommandAlias, comprehensive
edge case coverage across all modules.
