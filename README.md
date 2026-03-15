# Sift

A native macOS app for exploring parquet and DuckDB files through a chat-first desktop shell.

## Scope

- Native macOS app for exploring parquet, DuckDB, CSV, JSON, and remote data files
- Chat-first workflow with direct DuckDB command execution and natural language → SQL
- DuckDB CLI feature parity as a hard requirement
- Local-provider subscription workflow through installed CLIs, with API-key fallback
- 900+ unit tests across all modules

## Current App Features

### Chat commands

Sift supports 18 slash commands for workspace interaction:

| Command | Description |
|---------|-------------|
| `/help` | Show all available commands |
| `/sql <query>` | Run raw SQL against the active source |
| `/duckdb <args>` | Run raw DuckDB CLI arguments |
| `/copy` | Copy last query result to clipboard |
| `/rerun` | Re-execute the last command (or `/rerun N` for Nth) |
| `/history` | Show recent commands |
| `/export` | Copy full transcript to clipboard as Markdown |
| `/status` | Show workspace status summary |
| `/version` | Show Sift version info |
| `/bookmark` | Bookmark the last command |
| `/bookmarks` | List saved bookmarks |
| `/undo` | Remove the last user message and responses |
| `/stats` | Show session statistics |
| `/info` | Show active source details (path, size, type) |
| `/pins` | Show pinned transcript items |
| `/tags` | Show all tags in use |
| `/clear` | Clear the conversation transcript |
| `/reset` | Reset entire workspace (sources, bookmarks, transcript) |

### Source management

- **File formats**: `.parquet`, `.duckdb`, `.db`, `.csv`, `.tsv`, `.json`, `.jsonl`, `.ndjson`
- **Remote sources**: Import from `http://` or `https://` URLs
- **Batch import**: Import multiple files at once
- **Duplicate prevention**: Same-URL sources are not added twice
- **Source aliases**: User-defined short names for sources
- **Favorites**: Mark sources for quick access
- **Notes**: Attach freeform notes to any source
- **Validation**: Detect and clean up missing source files
- **Comparison**: Compare schemas of two sources side-by-side
- **Grouping**: View sources by kind, directory, or favorites
- **Search**: Find sources by name or alias

### Natural language query patterns

When a data source is active, Sift recognizes natural language and converts it to DuckDB SQL:

**File-based sources** (parquet, CSV, JSON):
- "Preview rows" / "Show schema" / "Count rows" / "Summarize"
- "Show columns" / "Show fields" / "Top N" / "Random sample"
- "Parquet schema" / "Metadata" (parquet-specific)

**DuckDB database sources**:
- "Show tables" / "Show columns" / "Show views" / "Show indexes"
- "Database info" / "Memory usage" / "Extensions" / "Version"
- "Describe [table]" / "Preview [table]" / "Count [table]"
- "Sample [table]" / "Summarize [table]"
- "Top N by [column] from [table]"
- "Distinct [column] in [table]"
- "Group by [column] in [table]"
- "Avg/sum/min/max [column] from [table]"
- "Order by [column] in [table]"
- "Filter [table] where [condition]"
- "[column] between X and Y in [table]"
- "Join [table1] and [table2] on [column]"

Any unrecognized query with an active source is sent to the configured AI provider for SQL generation.

### Transcript system

- **Pinning**: Pin important results for quick reference
- **Tagging**: Add string tags to organize transcript items
- **Search**: Full-text search with optional tag filtering
- **Compact mode**: View only user messages and command results
- **Pagination**: Navigate long transcripts in pages
- **Export**: Markdown, CSV, or plain text export
- **Deduplication**: Detect repeated user messages
- **Archival**: Archive old items while preserving pinned ones
- **Analytics**: Word count, character count, timing analysis

### Developer utilities

- **Command aliases**: Save short names for frequently used queries
- **Tab completion**: Type `/` to see matching slash commands
- **Query builder**: Fluent API for programmatic SQL construction (`DuckDBQueryBuilder`)
- **SQL formatter**: Uppercase SQL keywords for readability
- **SQL sanitizer**: Detect dangerous operations (DROP, DELETE, etc.)
- **Query complexity**: Estimate simple/moderate/complex query cost
- **Column type detection**: Map DuckDB types to categories (integer, decimal, text, etc.)
- **Output parser**: Extract row counts and detect errors in DuckDB output
- **Error recovery**: Suggest fixes for common DuckDB errors
- **Execution stats**: Track query timing, success rate, fastest execution

### Provider integration

- First-run setup launches before the main workspace until a default provider is configured
- Provider-backed chat routes through the selected local `claude`, `codex`, or `gemini` CLI
- API keys can be stored per provider in Keychain and are used as a fallback when local subscription auth is unavailable
- Natural language queries generate SQL via the provider, then execute it against the active source

### Workspace

- Session state persists locally, including settings, transcript history, sources, bookmarks, templates, aliases, and appearance preferences
- Hybrid SwiftUI + MetalKit architecture with Metal-backed status panels
- Dark/light/system appearance preference
- Contextual prompt suggestions based on active source and command history
- Query bookmarks and templates for reuse

## Build and test

```bash
swift build
swift test
./scripts/run_ui_smoke_tests.sh
```

`run_ui_smoke_tests.sh` launches an isolated app session, drives the UI with keyboard shortcuts, and verifies visible states with OCR.

## Metal replatform

The live app uses a hybrid rendering model:

- SwiftUI for the desktop shell, forms, transcript text, menus, and settings controls
- MetalKit for the dense visual status surfaces embedded in the workspace

The `MTKView` stays paused until state changes, then temporarily unpauses while work runs.

References:
- `docs/metal-replatform.md`
- `docs/metal-best-practices.md`
- `vendor/apple/Metal-Feature-Set-Tables.pdf`

If the Metal compiler is not available locally:
```bash
xcodebuild -downloadComponent metalToolchain
```

Build the app bundle:
```bash
./scripts/build_local_macos_app.sh
open "build/Sift.app"
```

## Keyboard commands

- `Cmd-O` open a source file (parquet, DuckDB, CSV, JSON)
- `Cmd-Shift-R` rerun setup
- `Cmd-Shift-D` toggle the diagnostics drawer
- `Cmd-L` focus the composer
- `Cmd-1` switch to Assistant
- `Cmd-2` switch to Transcripts
- `Cmd-3` switch to Setup
- `Cmd-4` switch to Settings

## Finder launcher

To avoid Terminal for local testing:

```bash
./scripts/build_local_launcher.sh    # Generate once
# Then double-click launcher/Launch Sift.app in Finder
```

If the build fails, check `logs/build-and-launch.log`.

## Contents

- `Package.swift` — repo-local Swift package (zero external dependencies)
- `Sources/` — app shell and support modules
- `Tests/` — 900+ unit tests across all modules
- `docs/` — design research and architecture docs
- `designs/` — UI design concepts
- `scripts/` — build, test, and deployment scripts

## Shared product rules

- The app exposes the raw DuckDB command and output path, not only AI-generated abstractions
- Provider secrets and refresh tokens live in Keychain, never in plist or flat files
- Initial implementation favors read-only exploration until explicit write workflows are specified
- SQL sanitizer flags dangerous operations (DROP, DELETE, UPDATE, etc.) for safety
