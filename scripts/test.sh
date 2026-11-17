#!/bin/sh
# Lint and unit tests, offline. Run scripts/bootstrap.sh once first.
#   scripts/test.sh                 luacheck, then every spec
#   scripts/test.sh --coverage      also write luacov.report.out
#   scripts/test.sh spec/tank_spec.lua   extra arguments go to busted
set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$REPO/.lua/bin"
cd "$REPO"

if [ ! -x "$BIN/busted" ]; then
    echo "Test toolchain missing. Run scripts/bootstrap.sh first." >&2
    exit 1
fi

COVERAGE=0
if [ "${1:-}" = "--coverage" ]; then COVERAGE=1; shift; fi

"$BIN/luacheck" --quiet .

if [ "$COVERAGE" = 1 ]; then
    rm -f luacov.stats.out luacov.report.out
    "$BIN/busted" --coverage "$@"
    "$BIN/luacov"
    rm -f luacov.stats.out
    # The summary table at the end of the report.
    sed -n '/^Summary/,$p' luacov.report.out
else
    "$BIN/busted" "$@"
fi
