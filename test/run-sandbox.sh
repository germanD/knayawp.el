#!/usr/bin/env bash
# test/run-sandbox.sh — Launch an isolated Emacs to test knayawp.el live
#
# Usage:
#   ./test/run-sandbox.sh           # GUI Emacs
#   ./test/run-sandbox.sh -nw       # Terminal Emacs
#
# What it does:
#   1. Starts Emacs -Q (no user config)
#   2. Bootstraps package.el so magit/vterm are available
#   3. Creates a throwaway git project in /tmp
#   4. Loads knayawp.el from this repo
#   5. Opens a test file — ready for M-x knayawp-layout-setup
#
# The sandbox session is fully disposable.  Close it and re-run
# this script any time you want a fresh test.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

exec emacs -Q "$@" \
     --eval "(setq inhibit-splash-screen t)" \
     -l "${REPO_ROOT}/test/sandbox.el"
