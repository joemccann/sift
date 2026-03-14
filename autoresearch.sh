#!/bin/bash
set -uo pipefail

# Quick syntax pre-check (catch obvious errors in <1s)
if ! swift build 2>&1 | tail -5; then
    echo "METRIC tests_passing=0"
    echo "METRIC build_time_s=0"
    exit 1
fi

# Run tests, capture timing
START=$(date +%s)
TEST_OUTPUT=$(swift test 2>&1) || true
END=$(date +%s)
BUILD_TIME=$((END - START))
TEST_EXIT=$?

# Count passing tests
PASSING=$(echo "$TEST_OUTPUT" | grep -c "passed (" || true)

echo "$TEST_OUTPUT" | tail -10

echo "METRIC tests_passing=$PASSING"
echo "METRIC build_time_s=$BUILD_TIME"

# Exit non-zero if any test failed
if echo "$TEST_OUTPUT" | grep -q "with [1-9].* failure"; then
    exit 1
fi
