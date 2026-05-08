#!/usr/bin/env bash
# Runs every *.tests.sh file in this directory and aggregates results.
set -u
DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
failed=0
total=0
for f in "$DIR"/*.tests.sh; do
    [ -f "$f" ] || continue
    total=$((total+1))
    bash "$f" || failed=$((failed+1))
    echo
done
if [ "$total" -eq 0 ]; then
    echo "No *.tests.sh files found in $DIR." >&2
    exit 1
fi
if [ "$failed" -eq 0 ]; then
    echo "All $total test file(s) passed."
    exit 0
else
    echo "$failed of $total test file(s) had failures."
    exit 1
fi
