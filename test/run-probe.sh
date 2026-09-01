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

# Create a private 700-mode temp directory.  git 2.55 checks the full
# parent-directory chain for world-readable permissions (755) and rejects
# repos whose ancestors are "accessible by others".  A 700-mode directory
# owned exclusively by the runner user passes that check for the repo dir
# itself; the GIT_CONFIG_COUNT vars below bypass the check for any
# remaining ancestors (e.g. $HOME with 755).
PROBE_TMPDIR="${HOME}/.knayawp-probe-tmp"
mkdir -p -m 700 "$PROBE_TMPDIR"
export TMPDIR="$PROBE_TMPDIR"

# All files/dirs created inside the sandbox inherit 600/700 permissions.
umask 077

# Route the tmux socket through $TMPDIR so sandboxed environments (agents,
# CI) can write it without needing /tmp/tmux-UID/ access.
export TMUX_TMPDIR="${TMPDIR}"

# Bypass git 2.55's safe.directory check (ownership + permissions) via
# environment variables.  This is more reliable than --global gitconfig
# edits, which require a writable $HOME/.gitconfig and may be overridden
# by system policy.
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0=safe.directory
export GIT_CONFIG_VALUE_0='*'

# If 'claude' is not on PATH, install a stub that runs /bin/sh so vterm
# panels stay alive.  Without this, vterm's vterm-kill-buffer-on-exit=t
# removes the Claude panel window the moment the missing process exits,
# leaving only 2 side windows instead of the expected 3.
if ! command -v claude >/dev/null 2>&1; then
    _stub_dir="${TMPDIR}/knayawp-ci-stubs"
    mkdir -p "$_stub_dir"
    printf '#!/bin/sh\nexec /bin/sh\n' > "$_stub_dir/claude"
    chmod +x "$_stub_dir/claude"
    export PATH="$_stub_dir:$PATH"
fi

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
