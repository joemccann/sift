# Sift

A native macOS app for exploring parquet and DuckDB files through a chat-first desktop shell.

## Scope

- Native macOS app for exploring parquet and DuckDB data
- Chat-first workflow with direct DuckDB command execution
- DuckDB CLI feature parity as a hard requirement
- Local-provider subscription workflow through installed CLIs, with API-key fallback
- Full-code-coverage expectation carried into the future implementation plan

## Current App Features

- **Natural language queries**: Ask questions in plain English — Sift sends the question to the selected AI provider, extracts the generated SQL, executes it against your data, and shows results directly. No SQL knowledge required.
- **Auto-execute SQL pipeline**: Provider responses containing SQL in fenced code blocks are automatically executed. Schema context is injected into prompts so the provider generates correct, schema-qualified queries.
- **Directory scanning**: Scan a directory to auto-discover `.duckdb`, `.parquet`, and `.db` files with configurable recursion depth (1–10 levels).
- **Copy-to-clipboard**: Each chat bubble has a copy button overlay for quick clipboard access.
- **Clear conversation**: Toolbar button to reset the transcript and start fresh.
- **Text selection**: Chat text is selectable for highlighting and copying.
- First-run setup launches before the main workspace until a default provider is configured.
- Settings are available both in-app and through the standard macOS Settings scene.
- Provider-backed chat routes through the selected local `claude`, `codex`, or `gemini` CLI.
- API keys can be stored per provider in Keychain and are used as a fallback when local subscription auth is unavailable.
- Session state persists locally, including settings, transcript history, imported sources, and the selected source.
- Raw DuckDB CLI passthrough is available from chat with `/duckdb ...` and from the diagnostics drawer.
- The workspace uses a hybrid SwiftUI plus MetalKit architecture, with Metal-backed status panels rendered through `MTKView`.
- Standard macOS commands are wired for opening sources and rerunning setup without leaving the app shell.
- Source-aware prompt planning supports direct SQL execution for local `.parquet`, `.duckdb`, and `.db` files.

## Build And Test

```bash
swift build
swift test
./scripts/build_local_macos_app.sh        # Produces build/Sift.app
./scripts/build_and_launch_local_app.sh   # Build and open
./scripts/run_ui_smoke_tests.sh           # Full UI smoke flow
./scripts/verify_nl_query.sh              # E2E natural language query verification
```

### Stable Code Signing (One-Time Setup)

By default, Sift uses ad-hoc code signing. This means macOS forgets permission grants (directory access, etc.) on every rebuild. To persist permissions across rebuilds, create a self-signed development certificate:

```bash
./scripts/setup_signing.sh
```

This creates a "Sift Development" certificate in your login keychain. Once installed, `build_local_macos_app.sh` automatically uses it. You only need to run this once — the certificate persists in your keychain.

### Test Scripts

- `run_ui_smoke_tests.sh` — Launches an isolated app session, drives the UI with keyboard shortcuts, and verifies visible states with OCR on the app window. Covers first-run setup, navigation, diagnostics, raw DuckDB CLI execution, provider-backed chat, source import, and parquet preview.
- `verify_nl_query.sh` — End-to-end verification that a natural language query produces correct results. Launches the app, completes setup, imports a DuckDB source, types a query, and verifies the expected output via OCR.

## Metal Replatform

The live app uses a hybrid rendering model:

- SwiftUI for the desktop shell, forms, transcript text, menus, and settings controls
- MetalKit for the dense visual status surfaces embedded in the workspace

That architecture is deliberate. For a macOS productivity app, a permanent full-screen game-style renderer is usually the wrong tradeoff. The current implementation keeps `MTKView` paused until state changes, then temporarily unpauses it only while work is actively running.

References for the current Metal work:

- `docs/metal-replatform.md`
- `docs/metal-best-practices.md`
- `vendor/apple/Metal-Feature-Set-Tables.pdf`
- `vendor/metal-guide/README.md`

If the Metal compiler is not available locally, install the optional Xcode component once:

```bash
xcodebuild -downloadComponent metalToolchain
```

The app-bundle build script precompiles `SiftMetalShaders.metallib` with:

- `scripts/compile_metal_library.sh`
- `scripts/build_local_macos_app.sh`

To open the app bundle:

```bash
./scripts/build_local_macos_app.sh
open "build/Sift.app"
```

## Keyboard Commands

- `Cmd-O` open a parquet, DuckDB, or SQLite source
- `Cmd-Shift-R` rerun setup
- `Cmd-Shift-D` toggle the diagnostics drawer
- `Cmd-L` focus the composer
- `Cmd-1` switch to Assistant
- `Cmd-2` switch to Transcripts
- `Cmd-3` switch to Setup
- `Cmd-4` switch to Settings

## Finder Launcher

To avoid Terminal for local testing, this repo includes a Finder-friendly launcher flow:

- Source AppleScript: `launcher/Launch Sift.applescript`
- Bundle build script: `scripts/build_local_macos_app.sh`
- Generator script: `scripts/build_local_launcher.sh`
- Build-and-open script: `scripts/build_and_launch_local_app.sh`
- Generated local macOS app build: `build/Sift.app`
- Generated local app: `launcher/Launch Sift.app`

To build the local macOS app bundle directly:

```bash
./scripts/build_local_macos_app.sh
```

That creates:

```text
build/Sift.app
```

To generate the double-clickable launcher once:

```bash
./scripts/build_local_launcher.sh
```

After that, double-click `launcher/Launch Sift.app` in Finder. It will:

- build `build/Sift.app`
- open the generated app bundle
- avoid opening Terminal

If the build or launch fails, check `logs/build-and-launch.log`.

## Scripts

| Script | Purpose |
|--------|---------|
| `build_local_macos_app.sh` | Build `Sift.app` bundle with code signing and entitlements |
| `build_and_launch_local_app.sh` | Build and open the app |
| `build_local_launcher.sh` | Generate Finder-friendly launcher |
| `compile_metal_library.sh` | Precompile Metal shaders to `.metallib` |
| `setup_signing.sh` | Create self-signed "Sift Development" certificate (one-time) |
| `run_ui_smoke_tests.sh` | End-to-end UI smoke test via AppleScript + OCR |
| `verify_nl_query.sh` | E2E natural language query verification |
| `ocr_window_text.swift` | Vision OCR helper used by test scripts |

## Contents

- `Package.swift`
  repo-local Swift package
- `Sources/`
  the runnable app shell and support modules
- `Tests/`
  unit coverage for planner, CLI adapter, provider chat, session persistence, and view-model seams
- `docs/macos-ui-research.md`
  Apple-source UI and UX guidance for current macOS design patterns
- `docs/technical-foundation.md`
  Shared architecture and testing guardrails
- `docs/subscription-oauth-debug-reference.md`
  Working auth reference captured from OAuth flow plus local CLI observations
- `docs/metal-replatform.md`
  Metal architecture, build rules, and downloaded references
- `docs/ai-chat-ux-best-practices.html`
  HTML research report for assistant UX, setup, settings, trust surfaces, and prompt-operation rules
- `docs/setup-and-settings-research.md`
  Setup gating, settings ownership, persistence seams, and future considerations
- `docs/metal-best-practices.md`
  Condensed Apple-source guidance for the hybrid SwiftUI plus MetalKit approach
- `docs/design-comparison.md`
  Comparison matrix and recommendation across the three design concepts
- `designs/`
  Three UI design concepts
- `.codex/skills/ai-chat-ux-best-practices/`
  Codex skill for assistant UX audits and refinements

## Shared Product Rules

- The app should expose the raw DuckDB command and output path, not only AI-generated abstractions.
- Provider secrets and refresh tokens must live in Keychain, never in plist or flat files.
- Initial implementation favors read-only exploration until explicit write workflows are specified.
