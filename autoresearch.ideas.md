# Autoresearch Ideas

## Promising Next Features
- Provider response caching — in-memory LRU cache
- Query parameterization — replace literals with $1, $2 params
- Smart error context — include recent transcript in error messages
- DuckDB "rename [table]" — ALTER TABLE pattern
- Source import history — track when sources were last queried
- Transcript search with tag filter — combine text search + tag
- Query complexity estimation — estimate query cost
- DuckDB type detection — map column types to display formats
- Batch command execution — run multiple queries in sequence

## Completed (72 experiments, 750 tests)
Everything prior plus: TranscriptExporter (CSV/plain text), TranscriptDeduplicator,
CommandAlias model, aggregate/order-by completeness, planner precedence fixes,
source lifecycle tests, Metal visualization edge cases, provider diagnostics coverage.
