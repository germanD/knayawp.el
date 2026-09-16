#!/usr/bin/env bash
# test/bootstrap-elpa.sh — Install ELPA packages needed by the probe suite.
#
# Idempotent: already-installed packages are skipped via package-installed-p.
# Run from a clean checkout before the probe suite to populate ~/.emacs.d/elpa.
#
# Packages installed: compat magit with-editor eat
# vterm is NOT installed here: it requires a native C module compiled at first
# use, and the compiled elpa-vterm apt package is used at runtime instead.
# Installing MELPA vterm would shadow the apt package and trigger an interactive
# y-or-n-p compile prompt in the -nw probe sessions, hanging them indefinitely.
#
# Usage:
#   bash test/bootstrap-elpa.sh

set -euo pipefail

emacs -Q --batch --eval "(progn \
  (require 'package) \
  (add-to-list 'package-archives '(\"melpa\" . \"https://melpa.org/packages/\")) \
  (package-initialize) \
  (condition-case e (package-refresh-contents) \
    (error (message \"Warning: package-refresh-contents failed: %S\" e))) \
  (dolist (pkg '(compat magit with-editor eat)) \
    (unless (package-installed-p pkg) \
      (ignore-errors (package-install pkg)))))" 2>&1 || true
