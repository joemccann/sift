#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$REPO_DIR/build"
APP_NAME="Sift.app"
APP_DIR="$BUILD_DIR/$APP_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_CONTENTS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
PLIST_PATH="$CONTENTS_DIR/Info.plist"
EXECUTABLE_NAME="SiftApp"
METAL_SOURCE="$REPO_DIR/Sources/SiftMetal/Shaders/SiftMetalShaders.metal"
METAL_LIBRARY_PATH="$RESOURCES_DIR/SiftMetalShaders.metallib"

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin:/Applications/Xcode.app/Contents/Developer/usr/bin:${PATH:-}"

/usr/bin/xcrun swift build --package-path "$REPO_DIR" >/dev/null

BIN_DIR="$("/usr/bin/xcrun" swift build --package-path "$REPO_DIR" --show-bin-path)"
APP_BINARY="$BIN_DIR/$EXECUTABLE_NAME"

if [[ ! -x "$APP_BINARY" ]]; then
  print -u2 -- "Built app binary not found at $APP_BINARY"
  exit 1
fi

/bin/rm -rf "$APP_DIR"
/bin/mkdir -p "$MACOS_CONTENTS_DIR" "$RESOURCES_DIR"
/bin/cp "$APP_BINARY" "$MACOS_CONTENTS_DIR/$EXECUTABLE_NAME"
/bin/chmod +x "$MACOS_CONTENTS_DIR/$EXECUTABLE_NAME"

if [[ -f "$METAL_SOURCE" ]]; then
  if ! "$SCRIPT_DIR/compile_metal_library.sh" "$METAL_SOURCE" "$METAL_LIBRARY_PATH" >/dev/null 2>&1; then
    print -u2 -- "Warning: failed to precompile Metal shaders; the app will fall back to runtime shader compilation."
  fi
fi

/usr/bin/plutil -create xml1 "$PLIST_PATH"
/usr/bin/plutil -replace CFBundleDevelopmentRegion -string "en" "$PLIST_PATH"
/usr/bin/plutil -replace CFBundleExecutable -string "$EXECUTABLE_NAME" "$PLIST_PATH"
/usr/bin/plutil -replace CFBundleIdentifier -string "local.sift.macos" "$PLIST_PATH"
/usr/bin/plutil -replace CFBundleInfoDictionaryVersion -string "6.0" "$PLIST_PATH"
/usr/bin/plutil -replace CFBundleName -string "Sift" "$PLIST_PATH"
/usr/bin/plutil -replace CFBundlePackageType -string "APPL" "$PLIST_PATH"
/usr/bin/plutil -replace CFBundleShortVersionString -string "0.1.0" "$PLIST_PATH"
/usr/bin/plutil -replace CFBundleVersion -string "1" "$PLIST_PATH"
/usr/bin/plutil -replace LSMinimumSystemVersion -string "15.0" "$PLIST_PATH"
/usr/bin/plutil -replace NSHighResolutionCapable -bool YES "$PLIST_PATH"
/usr/bin/plutil -replace NSPrincipalClass -string "NSApplication" "$PLIST_PATH"
/usr/bin/plutil -replace NSAppleMusicUsageDescription -string "Sift does not need access to Apple Music. You can safely deny this." "$PLIST_PATH"
/usr/bin/plutil -replace NSDesktopFolderUsageDescription -string "Sift needs access to open database and parquet files on your Desktop." "$PLIST_PATH"
/usr/bin/plutil -replace NSDocumentsFolderUsageDescription -string "Sift needs access to open database and parquet files in Documents." "$PLIST_PATH"
/usr/bin/plutil -replace NSDownloadsFolderUsageDescription -string "Sift needs access to open database and parquet files in Downloads." "$PLIST_PATH"

# Entitlements for file access so macOS remembers user approval between launches.
ENTITLEMENTS_PATH="$BUILD_DIR/Sift.entitlements"
cat > "$ENTITLEMENTS_PATH" <<ENTITLEMENTS_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
</dict>
</plist>
ENTITLEMENTS_EOF

# Sign with stable "Sift Development" certificate if available (preserves TCC grants across rebuilds).
# Falls back to ad-hoc signing if the certificate hasn't been set up yet.
CERT_NAME="Sift Development"
if security find-identity -p codesigning 2>/dev/null | grep -q "$CERT_NAME"; then
  /usr/bin/codesign --force --sign "$CERT_NAME" --entitlements "$ENTITLEMENTS_PATH" "$APP_DIR"
else
  print -u2 -- "Warning: '$CERT_NAME' certificate not found. Using ad-hoc signing (permissions won't persist across rebuilds)."
  print -u2 -- "Run: ./scripts/setup_signing.sh   to create a stable signing identity."
  /usr/bin/codesign --force --sign - --entitlements "$ENTITLEMENTS_PATH" "$APP_DIR"
fi

print -- "$APP_DIR"
