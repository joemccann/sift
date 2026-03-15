# Autoresearch Ideas

## Promising Next Features
- Provider response caching — in-memory LRU cache for recent responses
- Bulk tag operations — tag multiple items by search query
- Query parameterization — replace literals with $1, $2 params
- Transcript export as CSV — export command results as CSV text
- Provider model listing — list available models per provider
- DuckDB "limit N" modifier — append LIMIT to any table query
- Source health check — validate all sources exist on disk
- Transcript deduplication — detect duplicate user messages
- Command aliasing — user-defined short names for frequent queries
- Smart error context — include recent transcript in error messages

## Completed (70 experiments, 718 tests)
Everything prior plus: DuckDB aggregates (avg/sum/min/max with aliases),
order-by patterns, TranscriptTiming, source notes, query history search,
full Codable round-trips for all new properties, planner precedence fixes.
