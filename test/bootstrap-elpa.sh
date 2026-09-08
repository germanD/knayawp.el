#!/usr/bin/env bash
# test/bootstrap-elpa.sh — Install ELPA packages needed by the probe suite.
#
# Idempotent: already-installed packages are skipped via package-installed-p.
# Run from a clean checkout before the probe suite to populate ~/.emacs.d/elpa.
#
# Packages installed: vterm magit with-editor eat
#
# Usage:
#   bash test/bootstrap-elpa.sh

set -euo pipefail

emacs -batch --eval "(progn \
  (require 'package) \
  (add-to-list 'package-archives '(\"melpa\" . \"https://melpa.org/packages/\")) \
  (package-initialize) \
  (package-refresh-contents) \
  (dolist (pkg '(vterm magit with-editor eat)) \
    (unless (package-installed-p pkg) \
      (ignore-errors (package-install pkg)))))" 2>&1 || true
