#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LAUNCHER_SOURCE="$REPO_DIR/launcher/Launch Sift.applescript"
LAUNCHER_APP="$REPO_DIR/launcher/Launch Sift.app"

/bin/rm -rf "$LAUNCHER_APP"
/usr/bin/osacompile -o "$LAUNCHER_APP" "$LAUNCHER_SOURCE"

print -- "$LAUNCHER_APP"
