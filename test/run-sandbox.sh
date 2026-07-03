#!/usr/bin/env bash
# test/run-sandbox.sh — Launch an isolated Emacs to test knayawp.el live
#
# Usage:
#   ./test/run-sandbox.sh                       # GUI Emacs
#   ./test/run-sandbox.sh -nw                   # Terminal Emacs
#   ./test/run-sandbox.sh FILE                  # also open FILE (e.g. a probe)
#   ./test/run-sandbox.sh -nw .tmp/pr76-scenario3-probe.el
#
# Any argument starting with "-" is forwarded to Emacs (e.g. -nw).
# A single non-flag argument is an EXTRA file to open in the sandbox
# alongside the test project — handy for opening a probe file without
# typing its absolute path each restart (the sandbox project lives in
# /tmp, so the probe file is otherwise an awkward C-x C-f away).
#
# What it does:
#   1. Starts Emacs -Q (no user config)
#   2. Bootstraps package.el so magit/vterm are available
#   3. Creates a throwaway git project in /tmp
#   4. Loads knayawp.el from this repo
#   5. Opens a test file — ready for M-x knayawp-layout-setup
#   6. If an EXTRA file was given, opens it too (shown, not selected, so
#      C-c k l still targets the /tmp sandbox project)
#
# The sandbox session is fully disposable.  Close it and re-run
# this script any time you want a fresh test.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

emacs_args=()
extra_file=""
for arg in "$@"; do
  case "$arg" in
    -*)
      emacs_args+=("$arg")
      ;;
    *)
      if [[ -n "$extra_file" ]]; then
        echo "run-sandbox.sh: only one EXTRA file may be given (extra: $arg)" >&2
        exit 1
      fi
      extra_file="$arg"
      ;;
  esac
done

if [[ -n "$extra_file" ]]; then
  if [[ ! -e "$extra_file" ]]; then
    echo "run-sandbox.sh: EXTRA file not found: $extra_file" >&2
    exit 1
  fi
  # Resolve to an absolute path: sandbox.el runs with /tmp as its
  # default-directory, so a relative path would not be found there.
  extra_file="$(cd "$(dirname "$extra_file")" && pwd)/$(basename "$extra_file")"
  export KNAYAWP_SANDBOX_EXTRA_FILE="$extra_file"
fi

exec emacs -Q "${emacs_args[@]+"${emacs_args[@]}"}" \
     --eval "(setq inhibit-splash-screen t)" \
     -l "${REPO_ROOT}/test/sandbox.el"
