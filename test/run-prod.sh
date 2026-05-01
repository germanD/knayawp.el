#!/usr/bin/env bash
# test/run-prod.sh — Launch Emacs with full user config + knayawp.el loaded
#
# Usage:
#   ./test/run-prod.sh [FILE]          # GUI Emacs
#   ./test/run-prod.sh -nw [FILE]      # Terminal Emacs
#
# Unlike run-sandbox.sh (which uses -Q), this loads your normal
# .emacs config so you can test knayawp.el alongside your real
# packages (colors, company-mode, language modes, etc).
#
# Launches a separate Emacs process — does not affect other
# running Emacs instances or emacsclient sessions.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

exec emacs \
     --eval "(progn
               (load \"${REPO_ROOT}/knayawp.el\")
               (global-set-key (kbd \"C-c k\") knayawp-command-map)
               (message \"knayawp.el loaded — C-c k l to set up layout\"))" \
     "$@"
