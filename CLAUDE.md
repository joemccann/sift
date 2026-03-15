# Sift

Chat-first native macOS shell for exploring parquet and DuckDB files. Extracted from the market-data-warehouse repo's `macos/` directory.

## Project Layout

```
sift/
├── Package.swift               # Swift package manifest (zero external deps)
├── Sources/
│   ├── SiftApp/                # @main entry point
│   ├── SiftCore/               # Shared models, planner, utilities
│   │   ├── AssistantPlanner    # Prompt routing, 14 DuckDB pattern extractors
│   │   ├── TranscriptModels    # Transcript items, analytics, filtering, export
│   │   ├── DataSource          # Source model, query builders, SQL utilities
│   │   ├── AppSettings         # Settings, bookmarks, templates, aliases
│   │   └── MetalWorkspace*     # Metal state snapshot model
│   ├── DuckDBAdapter/          # DuckDB CLI binary locator, executor, argument parser
│   ├── SiftKit/                # SwiftUI views, view model, session, keychain, provider chat
│   │   ├── SiftViewModel       # Main view model (116 public methods/properties)
│   │   ├── ProviderChatService # CLI integration, SQL extraction
│   │   ├── SiftRootView        # Main SwiftUI view
│   │   └── AppSessionStore     # JSON session persistence
│   └── SiftMetal/              # MetalKit workspace surfaces and shader library
├── Tests/                      # 900+ unit tests
│   ├── SiftCoreTests/          # ~512 tests (planner, models, utilities)
│   ├── DuckDBAdapterTests/     # ~45 tests
│   ├── SiftKitTests/           # ~345 tests (ViewModel, provider, session)
│   └── SiftMetalTests/         # ~29 tests
├── scripts/                    # Build, test, and deployment scripts
├── docs/                       # Design research and architecture docs
├── designs/                    # UI design concepts
└── vendor/                     # Apple Metal references
```

## Build and Test

```bash
swift build
swift test
./scripts/build_local_macos_app.sh        # Produces build/Sift.app
./scripts/run_ui_smoke_tests.sh           # Full UI smoke flow
```

If the Metal compiler is missing:
```bash
xcodebuild -downloadComponent metalToolchain
```

## Key Details

- Zero external Swift dependencies (pure Apple frameworks)
- Session persists at `~/Library/Application Support/Sift/session.json`
- Keychain service: `local.sift.macos`
- Env overrides: `SIFT_SESSION_FILE`, `SIFT_AUTOMATION_PICK_SOURCE`
- Provider chat routes through installed local `claude`, `codex`, or `gemini` CLIs
- Hybrid SwiftUI + MetalKit architecture: native controls with `MTKView`-backed workspace panels
- Metal shader library: `SiftMetalShaders`

## Architecture

### SiftCore modules

- `AssistantPlanner` — routes user prompts to actions: slash commands, DuckDB patterns, provider chat, or natural language SQL generation. Contains 14 pattern extractors for table-specific operations.
- `CommandRegistry` — registry of all 18 slash commands with tab-completion support.
- `TranscriptModels` — `TranscriptItem` with pinning, tagging, and codable support. Includes `TranscriptAnalytics`, `TranscriptFilter`, `TranscriptTiming`, `TranscriptExporter`, `TranscriptDeduplicator`, `TranscriptArchiver`, and `QueryHistoryManager`.
- `DataSource` — source model with aliases, favorites, notes, file validation, remote URL support, and query builders (`selectQuery`, `countQuery`, `summarizeQuery`, `describeQuery`, `duckDBReadExpression`). Also contains `DuckDBQueryBuilder` (fluent API), `SQLFormatter`, `SQLSanitizer`, `PromptContextBuilder`, `QueryComplexityEstimator`, `DuckDBColumnType`, `DuckDBOutputParser`, `DuckDBErrorRecovery`, `SourceComparison`, and `SourceStatistics`.
- `AppSettings` — settings with provider preferences, bookmarks, query templates, command aliases, and appearance preference.

### SiftKit modules

- `SiftViewModel` — 116 public methods/properties covering source management, transcript operations, slash command handling, execution stats, search, tag/pin/favorite operations, and session export.
- `ProviderChatService` — CLI process execution for Claude/OpenAI/Gemini with JSON response parsing, SQL extraction from markdown code blocks, and API key fallback.
- `AppSessionStore` — JSON persistence with full Codable round-trip for all model types.

### Supported file formats

| Format | Extensions | DuckDB Function |
|--------|-----------|----------------|
| Parquet | `.parquet` | `read_parquet()` |
| DuckDB | `.duckdb`, `.db` | Direct query |
| CSV | `.csv`, `.tsv` | `read_csv()` |
| JSON | `.json`, `.jsonl`, `.ndjson` | `read_json()` |
| Remote | Any above via `http://`/`https://` | Same functions |

## Testing

900+ unit tests across all modules. Run:
```bash
swift test
```

Tests cover:
- All 18 slash commands and their handlers
- All 14 DuckDB pattern extractors with edge cases
- All file format planner paths (parquet, CSV, JSON, DuckDB)
- Provider diagnostics, CLI invocation, SQL extraction
- Session persistence round-trips for all model types
- Metal visualization signal generation
- Error handling (DuckDB unavailable, provider errors, missing API keys)
- End-to-end integration workflows

For end-to-end UI verification:
```bash
./scripts/run_ui_smoke_tests.sh
```
