#!/bin/bash
set -euo pipefail
# Ensure all tests pass — only show failures
swift test 2>&1 | grep -E "(FAIL|failed|error:|unexpected)" | head -50 || true
# Verify exit code
swift test 2>&1 > /dev/null
