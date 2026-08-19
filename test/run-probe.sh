#!/usr/bin/env bash
# test/run-probe.sh — Run a self-running knayawp "auto" probe headlessly.
#
# Usage:
#   test/run-probe.sh PROBE.el [COLSxROWS]
#
# Why tmux: `emacs -nw` needs a real controlling tty, and we want a
# DETERMINISTIC frame size so window-geometry assertions are stable.
# A detached tmux session provides both — a pty plus a fixed COLSxROWS.
# (`-batch` has no frame at all, so it cannot exercise the side-window
# layout these probes inspect.)
#
# The probe writes its PASS/FAIL report to a temp file named by
# KNAYAWP_PROBE_RESULTS; this script waits for it, prints it, and tears
# the session down.  A probe-side watchdog guarantees the file appears
# even if the flow under test stalls.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROBE="${1:?usage: run-probe.sh PROBE.el [COLSxROWS]}"
GEOM="${2:-200x50}"
COLS="${GEOM%x*}"
ROWS="${GEOM#*x}"

if [ ! -f "$PROBE" ]; then
    echo "run-probe: probe not found: $PROBE" >&2
    exit 1
fi

RESULTS="$(mktemp -t knayawp-probe.XXXXXX)"
SESSION="knwprobe-$$"

cleanup() {
    tmux kill-session -t "$SESSION" 2>/dev/null || true
    rm -f "$RESULTS"
}
trap cleanup EXIT

# Route the tmux socket through $TMPDIR so sandboxed environments (agents,
# CI) can write it without needing /tmp/tmux-UID/ access.
export TMUX_TMPDIR="${TMPDIR:-/tmp}"

# Launch Emacs in a fixed-size detached tmux session.  sandbox.el sets up
# the throwaway project + dependencies; probe-lib.el provides the
# assertion harness; the probe drives the scenario and writes $RESULTS.
tmux new-session -d -s "$SESSION" -x "$COLS" -y "$ROWS" \
    "KNAYAWP_PROBE_RESULTS='$RESULTS' exec emacs -nw -Q \
        -l '$REPO_ROOT/test/sandbox.el' \
        -l '$REPO_ROOT/test/probe-lib.el' \
        -l '$PROBE'"

# Wait for the report file (non-empty) or the session to vanish.
deadline=$(( SECONDS + 120 ))
while [ ! -s "$RESULTS" ]; do
    if ! tmux has-session -t "$SESSION" 2>/dev/null; then
        break
    fi
    if [ "$SECONDS" -ge "$deadline" ]; then
        echo "run-probe: timed out after 120s waiting for results" >&2
        echo "--- tmux pane capture ---" >&2
        tmux capture-pane -t "$SESSION" -p 2>/dev/null >&2 || true
        break
    fi
    sleep 0.5
done

echo "===== PROBE: $(basename "$PROBE")  geom=${GEOM} ====="
if [ -s "$RESULTS" ]; then
    cat "$RESULTS"
else
    echo "(no results written — Emacs exited early or the probe never finished)"
    exit 1
fi
