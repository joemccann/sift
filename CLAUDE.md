# Sift

Chat-first native macOS shell for exploring parquet and DuckDB files. Extracted from the market-data-warehouse repo's `macos/` directory.

## Project Layout

```
sift/
├── Package.swift               # Swift package manifest
├── Sources/
│   ├── SiftApp/                # @main entry point
│   ├── SiftCore/               # Shared models (settings, data source, transcript, Metal snapshot)
│   ├── DuckDBAdapter/          # DuckDB CLI binary locator, executor, argument parser
│   ├── SiftKit/                # SwiftUI views, view model, session, keychain, provider chat
│   └── SiftMetal/              # MetalKit workspace surfaces and shader library
├── Tests/
│   ├── SiftCoreTests/
│   ├── DuckDBAdapterTests/
│   ├── SiftKitTests/
│   └── SiftMetalTests/
├── scripts/
│   ├── build_local_macos_app.sh      # Build Sift.app bundle
│   ├── build_and_launch_local_app.sh # Build and open the app
│   ├── build_local_launcher.sh       # Generate Finder launcher
│   ├── compile_metal_library.sh      # Precompile Metal shaders
│   ├── run_ui_smoke_tests.sh         # End-to-end UI verification
│   └── ocr_window_text.swift         # Vision OCR helper for smoke tests
├── launcher/                   # Finder-friendly launcher AppleScript
├── docs/                       # Design research and architecture docs
├── designs/                    # UI design concepts
├── renders/                    # Design render artifacts
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

## Testing

All modules have unit tests. Run:
```bash
swift test
```

For end-to-end UI verification:
```bash
./scripts/run_ui_smoke_tests.sh
```
