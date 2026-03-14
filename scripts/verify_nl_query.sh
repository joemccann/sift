#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$REPO_DIR/logs"
LOG_PATH="$LOG_DIR/verify-nl-query.log"
APP_PATH="$("$SCRIPT_DIR/build_local_macos_app.sh")"
TMP_DIR="$(mktemp -d)"
SESSION_FILE="$TMP_DIR/session.json"
SOURCE_PATH="$HOME/market-warehouse/duckdb/market.duckdb"
WINDOW_CAPTURE_PATH="$TMP_DIR/window.png"
SESSION_ENV_KEY="SIFT_SESSION_FILE"
SOURCE_PICK_ENV_KEY="SIFT_AUTOMATION_PICK_SOURCE"
EXPECTED_ROW_COUNT="16996741"

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin:/Applications/Xcode.app/Contents/Developer/usr/bin:${PATH:-}"

mkdir -p "$LOG_DIR"

cleanup() {
  /bin/launchctl unsetenv "$SESSION_ENV_KEY" >/dev/null 2>&1 || true
  /bin/launchctl unsetenv "$SOURCE_PICK_ENV_KEY" >/dev/null 2>&1 || true
  if [[ -n "${APP_PID:-}" ]] && kill -0 "$APP_PID" >/dev/null 2>&1; then
    kill "$APP_PID" >/dev/null 2>&1 || true
    wait "$APP_PID" >/dev/null 2>&1 || true
  fi
  /usr/bin/pkill -x SiftApp >/dev/null 2>&1 || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

window_bounds() {
  /usr/bin/osascript - "$APP_PID" <<'APPLESCRIPT'
on run argv
  set pidValue to item 1 of argv as integer
  tell application "System Events"
    try
      tell (first application process whose unix id is pidValue)
        set frontmost to true
        if (count of windows) is 0 then
          return ""
        end if
        tell window 1
          set {xPos, yPos} to position
          set {winWidth, winHeight} to size
          return (xPos as text) & "," & (yPos as text) & "," & (winWidth as text) & "," & (winHeight as text)
        end tell
      end tell
    on error
      return ""
    end try
  end tell
end run
APPLESCRIPT
}

window_text() {
  local bounds
  bounds="$(window_bounds)"
  if [[ -z "$bounds" ]]; then
    return 0
  fi
  /usr/sbin/screencapture -x -R"$bounds" "$WINDOW_CAPTURE_PATH"
  /usr/bin/swift "$SCRIPT_DIR/ocr_window_text.swift" "$WINDOW_CAPTURE_PATH"
}

wait_for_text() {
  local expected="$1"
  local timeout="${2:-30}"
  local started_at="$SECONDS"
  while (( SECONDS - started_at < timeout )); do
    if window_text | /usr/bin/grep -Fqi "$expected"; then
      return 0
    fi
    /bin/sleep 0.75
  done
  echo "Timed out waiting for UI text: $expected" | tee -a "$LOG_PATH" >&2
  return 1
}

send_key_code() {
  local key_code="$1"
  /usr/bin/osascript - "$APP_PID" "$key_code" <<'APPLESCRIPT'
on run argv
  set pidValue to item 1 of argv as integer
  set keyCodeValue to item 2 of argv as integer
  tell application "System Events"
    tell (first application process whose unix id is pidValue)
      set frontmost to true
    end tell
    key code keyCodeValue
  end tell
end run
APPLESCRIPT
}

send_shortcut() {
  local key="$1"
  local modifiers="$2"
  /usr/bin/osascript - "$APP_PID" "$key" "$modifiers" <<'APPLESCRIPT'
on run argv
  set pidValue to item 1 of argv as integer
  set keyValue to item 2 of argv
  set modifierSpec to item 3 of argv
  set modifierList to {}
  if modifierSpec contains "command" then set end of modifierList to command down
  if modifierSpec contains "shift" then set end of modifierList to shift down
  if modifierSpec contains "option" then set end of modifierList to option down
  if modifierSpec contains "control" then set end of modifierList to control down
  tell application "System Events"
    tell (first application process whose unix id is pidValue)
      set frontmost to true
    end tell
    keystroke keyValue using modifierList
  end tell
end run
APPLESCRIPT
}

type_text() {
  local text="$1"
  /usr/bin/osascript - "$APP_PID" "$text" <<'APPLESCRIPT'
on run argv
  set pidValue to item 1 of argv as integer
  set typedText to item 2 of argv
  tell application "System Events"
    tell (first application process whose unix id is pidValue)
      set frontmost to true
    end tell
    keystroke typedText
  end tell
end run
APPLESCRIPT
}

log_step() {
  local message="$1"
  echo "[$(/bin/date '+%Y-%m-%d %H:%M:%S')] $message" | tee -a "$LOG_PATH"
}

# Kill any existing Sift instances
/usr/bin/osascript -e 'tell application id "local.sift.macos" to quit' >/dev/null 2>&1 || true
/usr/bin/pkill -x SiftApp >/dev/null 2>&1 || true
sleep 1

# Set up environment for automation
/bin/launchctl setenv "$SESSION_ENV_KEY" "$SESSION_FILE"
/bin/launchctl setenv "$SOURCE_PICK_ENV_KEY" "$SOURCE_PATH"

# Launch the app
/usr/bin/open -na "$APP_PATH"
sleep 2

for _ in {1..100}; do
  APP_PID="$(/usr/bin/pgrep -nx SiftApp || true)"
  if [[ -n "$APP_PID" ]]; then
    break
  fi
  /bin/sleep 0.2
done

if [[ -z "${APP_PID:-}" ]]; then
  echo "Failed to locate app process." | tee -a "$LOG_PATH" >&2
  exit 1
fi

/bin/launchctl unsetenv "$SESSION_ENV_KEY"
/bin/launchctl unsetenv "$SOURCE_PICK_ENV_KEY"

log_step "App launched with PID $APP_PID"

# Step 1: Complete setup (accept defaults — Claude is the default provider)
log_step "Waiting for setup screen"
wait_for_text "Welcome to Sift" 30
log_step "Accepting default setup (press Enter)"
send_key_code 36
wait_for_text "Setup Complete" 15

# Step 2: Import the DuckDB source
log_step "Opening source (Cmd+O triggers automation pick)"
send_shortcut "o" "command"
wait_for_text "market.duckdb" 15

# Step 3: Type the natural language query
log_step "Focusing composer and typing query"
sleep 1
send_shortcut "l" "command"
sleep 0.5
type_text "provide me with the total number of rows in the database"
sleep 0.5
send_key_code 36

# Step 4: Wait for the result (provider call + auto-execute can take a while)
log_step "Waiting for query result (up to 120s)..."
RESULT_FOUND=false
STARTED=$SECONDS
while (( SECONDS - STARTED < 120 )); do
  TEXT="$(window_text 2>/dev/null || true)"
  if echo "$TEXT" | /usr/bin/grep -q "$EXPECTED_ROW_COUNT"; then
    RESULT_FOUND=true
    log_step "SUCCESS: Found expected row count $EXPECTED_ROW_COUNT in UI"
    break
  fi
  if echo "$TEXT" | /usr/bin/grep -qi "exit code"; then
    log_step "Query completed. Checking result..."
    echo "$TEXT" >> "$LOG_PATH"
    if echo "$TEXT" | /usr/bin/grep -q "$EXPECTED_ROW_COUNT"; then
      RESULT_FOUND=true
      log_step "SUCCESS: Found expected row count $EXPECTED_ROW_COUNT"
      break
    else
      log_step "Result did not contain expected count. Current UI text:"
      echo "$TEXT" | tee -a "$LOG_PATH"
      break
    fi
  fi
  /bin/sleep 2
done

if $RESULT_FOUND; then
  echo ""
  echo "========================================="
  echo "  VERIFICATION PASSED"
  echo "  Expected: $EXPECTED_ROW_COUNT"
  echo "  Found in UI output"
  echo "========================================="
  exit 0
else
  echo ""
  echo "========================================="
  echo "  VERIFICATION FAILED"
  echo "  Expected: $EXPECTED_ROW_COUNT"
  echo "  Not found in UI"
  echo "========================================="
  log_step "Final UI text dump:"
  window_text 2>/dev/null | tee -a "$LOG_PATH" || true
  exit 1
fi
