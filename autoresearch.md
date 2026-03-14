# Autoresearch: Sift Functionality Improvements

## Objective
Systematically add missing functionality to Sift, a chat-first native macOS shell for exploring parquet and DuckDB files. Each experiment adds a discrete feature with tests, building toward a more capable and polished app.

## Metrics
- **Primary**: `tests_passing` (count, higher is better) — total number of passing unit tests
- **Secondary**: `build_time_s` — build time in seconds (monitor for regressions)

## How to Run
`./autoresearch.sh` — builds, runs tests, outputs `METRIC name=number` lines.

## Files in Scope
All files the agent may modify:

### Sources
- `Sources/SiftCore/AssistantPlanner.swift` — prompt routing, command planning, prompt library
- `Sources/SiftCore/TranscriptModels.swift` — transcript item types, roles, kinds
- `Sources/SiftCore/DataSource.swift` — data source model (parquet, duckdb)
- `Sources/SiftCore/AppSettings.swift` — settings, provider preferences, session snapshot
- `Sources/SiftCore/MetalWorkspaceSnapshot.swift` — Metal state snapshot model
- `Sources/SiftKit/SiftViewModel.swift` — main view model, all app logic
- `Sources/SiftKit/SiftRootView.swift` — main SwiftUI view, sidebar, transcript, composer
- `Sources/SiftKit/ProviderChatService.swift` — provider CLI integration
- `Sources/SiftKit/ProviderDiagnostics.swift` — CLI/key detection
- `Sources/SiftKit/SetupFlowView.swift` — setup flow and settings pane
- `Sources/SiftKit/AppSessionStore.swift` — session persistence
- `Sources/SiftKit/KeychainStore.swift` — keychain secret storage
- `Sources/SiftKit/MetalStatusPanel.swift` — Metal status panel SwiftUI wrapper
- `Sources/SiftKit/SourcePicker.swift` — NSOpenPanel file picker
- `Sources/SiftMetal/MetalWorkspaceSurface.swift` — Metal rendering surface
- `Sources/SiftMetal/MetalWorkspaceVisualization.swift` — visualization data mapping
- `Sources/SiftMetal/MetalDeviceCapabilities.swift` — GPU capability detection
- `Sources/SiftMetal/MetalShaderLibrary.swift` — shader library loading
- `Sources/DuckDBAdapter/DuckDBCLIExecutor.swift` — DuckDB CLI process execution
- `Sources/DuckDBAdapter/DuckDBBinaryLocator.swift` — DuckDB binary discovery
- `Sources/DuckDBAdapter/DuckDBRawArgumentParser.swift` — raw argument parsing

### Tests
- `Tests/SiftCoreTests/AssistantPlannerTests.swift`
- `Tests/DuckDBAdapterTests/DuckDBAdapterTests.swift`
- `Tests/SiftKitTests/SiftViewModelTests.swift`
- `Tests/SiftKitTests/ProviderChatServiceTests.swift`
- `Tests/SiftKitTests/AppSessionStoreTests.swift`
- `Tests/SiftKitTests/TestSupport.swift`
- `Tests/SiftMetalTests/MetalWorkspaceSurfaceTests.swift`

## Off Limits
- `Package.swift` — zero external dependencies constraint
- `Sources/SiftApp/SiftApp.swift` — keep minimal, delegate to SiftKit
- Metal shader files in `Sources/SiftMetal/Shaders/`
- `scripts/` directory
- `docs/`, `designs/`, `renders/`, `vendor/`

## Constraints
- All existing tests must continue to pass
- Zero external Swift dependencies (pure Apple frameworks only)
- New features must have unit tests
- Swift 6.2, macOS 15+, `@Sendable` concurrency safety
- Each experiment = one discrete feature addition

## Feature Backlog (priority order)
1. **Source removal** — remove a source from the sidebar
2. **CSV file support** — accept .csv files as data sources
3. **`/help` command** — discoverable list of all chat commands
4. **Source drag-and-drop** — drop files onto the app window
5. **Richer AssistantPlanner** — more DuckDB command patterns (SUMMARIZE, column stats, etc.)
6. **Query re-run** — re-execute a previous command from transcript
7. **Export results** — copy/save query output to clipboard or file
8. **Multiple source types** — JSON, Excel support via DuckDB read functions
9. **Query cancellation** — cancel running DuckDB commands
10. **Conversation search** — find text in transcript

## What's Been Tried
(Updated as experiments accumulate)
