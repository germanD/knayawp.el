#!/usr/bin/env bash
# test/run-probes.sh — Run the headless probe regression suite.
#
# Usage:
#   test/run-probes.sh [DIR]
#
# Runs every `*.el` probe in DIR (default test/probes/) through
# test/run-probe.sh and prints a one-line STATUS per probe.  Exits
# non-zero if any probe is not GREEN, so it is usable as a CI gate.
#
# A probe may request a specific frame geometry with a header comment:
#   ;; Probe-Geometry: 40x50
# Otherwise the KNAYAWP_PROBE_GEOM env var is used (default 200x50).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="${1:-$REPO_ROOT/test/probes}"
RUNNER="$REPO_ROOT/test/run-probe.sh"

shopt -s nullglob
probes=("$DIR"/*.el)
if [ ${#probes[@]} -eq 0 ]; then
    echo "run-probes: no probes found in $DIR"
    exit 0
fi

echo "Running ${#probes[@]} probe(s) from $DIR"
echo

failures=0
for probe in "${probes[@]}"; do
    name="$(basename "$probe")"
    # Probe-level geometry override; fall back to env var then runner default.
    geom="$(grep -m1 -oE 'Probe-Geometry:[[:space:]]*[0-9]+x[0-9]+' "$probe" \
                | grep -oE '[0-9]+x[0-9]+' || true)"
    if [ -z "$geom" ] && [ -n "${KNAYAWP_PROBE_GEOM:-}" ]; then
        geom="$KNAYAWP_PROBE_GEOM"
    fi
    START=$SECONDS
    out="$("$RUNNER" "$probe" ${geom:+"$geom"} 2>&1)"
    ELAPSED=$(( SECONDS - START ))
    status="$(printf '%s\n' "$out" | grep -oE 'STATUS: [A-Z]+' | tail -1)"
    result="$(printf '%s\n' "$out" | grep -oE 'RESULT:.*' | tail -1)"
    # Distinguish INCOMPLETE (watchdog) from RED (assertion failure).
    display_status="${status:-NO-STATUS}"
    if printf '%s' "$status" | grep -q 'STATUS: INCOMPLETE'; then
        display_status="INCOMPLETE"
    elif printf '%s' "$status" | grep -q 'STATUS: RED'; then
        display_status="RED"
    elif printf '%s' "$status" | grep -q 'STATUS: GREEN'; then
        display_status="GREEN"
    fi
    printf '%-44s %-18s %s [%ds]\n' "$name" "$display_status" "$result" "$ELAPSED"
    if ! printf '%s' "$status" | grep -q 'STATUS: GREEN'; then
        failures=$((failures + 1))
        echo "----- full output: $name -----"
        printf '%s\n' "$out"
        echo "-------------------------------"
    fi
done

echo
if [ "$failures" -eq 0 ]; then
    echo "Suite GREEN: all ${#probes[@]} probe(s) passed."
else
    echo "Suite RED: $failures of ${#probes[@]} probe(s) failed."
fi
exit $(( failures > 0 ? 1 : 0 ))
