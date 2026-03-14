# Autoresearch Ideas

## Promising Next Features
- Provider response caching — simple in-memory LRU cache
- Bulk tag operations — tag all items matching a search query
- Query parameterization — replace literals with $1, $2 params
- Transcript item duration — time between consecutive items
- DuckDB "order by [column] in [table]" — sort pattern
- DuckDB "avg/sum/min/max [column] in [table]" — aggregate function patterns
- Source notes — attach freeform notes to sources
- Transcript export as CSV — export command results as CSV
- Query history search — search previously executed SQL
- Provider model listing — list available models per provider

## Completed (63 experiments, 650 tests)
All prior features plus: source favorites/comparison, error recovery suggestions,
DuckDB distinct/group-by/where-filter/join/top-N-by-column patterns,
TranscriptFilter utility, source grouping by directory, combined workflow tests.
