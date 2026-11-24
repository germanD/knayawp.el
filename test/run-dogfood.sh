#!/usr/bin/env bash
# test/run-dogfood.sh — Per-project isolated-daemon dogfood launcher
#
# Successor to run-prod.sh for the author's multi-project dogfooding.
# Starts (or reattaches to) one isolated Emacs daemon per project, each
# installing knayawp exactly as an end user would — via
# `package-vc-install-from-checkout` from this local checkout (real
# autoloads + byte-compile), in a dedicated profile directory.
#
# Usage:
#   ./test/run-dogfood.sh PROJECT_PATH            # GUI frame
#   ./test/run-dogfood.sh -nw PROJECT_PATH        # terminal frame
#   ./test/run-dogfood.sh --no-layout PROJECT_PATH  # skip knayawp-layout-setup
#
# What it does (implements the "Dogfooding model — per-project isolated
# daemon" section of kb/spec.md; aligns with ADR-006):
#   1. Derives a sanitized <project> slug from PROJECT_PATH's basename and
#      a daemon/server name "knayawp-<project>".  Per ADR-006, the daemon
#      name is THE per-instance identity lever: knayawp reuses the daemon's
#      own server (branch 1 of knayawp--ensure-editor-server) and never
#      reads `knayawp-editor-server-name` in the daemon model.
#   2. Creates an isolated Emacs profile dir (own user-emacs-directory, so
#      elpa/, recentf, desktop, and a per-profile server-socket-dir are all
#      isolated).  Default location:
#        ${XDG_DATA_HOME:-$HOME/.local/share}/knayawp-dogfood/<project>/
#      Override the parent with KNAYAWP_DOGFOOD_HOME.
#   3. (Re)generates a minimal init.el in that profile that bootstraps
#      package.el (GNU ELPA + MELPA), installs knayawp from this checkout,
#      requires it, and enables knayawp-mode.  Regenerated on every run so a
#      re-run always picks up the latest checkout path / template.
#   4. Starts a NAMED daemon:
#        emacs -q --init-directory=<profile> -l <profile>/init.el \
#              --daemon=knayawp-<project>
#      Note on -q + explicit -l (divergence from the spec's literal launch
#      line, same isolation intent): --init-directory sets
#      user-emacs-directory so elpa/, recentf, and desktop isolate into the
#      profile, but Emacs's startup still loads a personal ~/.emacs FIRST
#      when one exists (it does on the author's box), so the profile init.el
#      would never run.  -q suppresses the personal init; -l then loads the
#      generated profile init.el explicitly.  This guarantees the spec's "no
#      personal config bleeds in" isolation on any machine.
#   5. Attaches a frame:  emacsclient -c -s knayawp-<project>
#                                     --eval '(knayawp-layout-setup)'
#      (or -nw for a terminal frame).
#   6. If the daemon for that project is already running, it just attaches a
#      new frame instead of starting a second daemon — the workspace survives
#      a disconnected client frame and is reattachable.
#
# NETWORK: the FIRST run for a given project installs knayawp's deps
# (magit and the terminal backend) from GNU ELPA / MELPA, so it needs
# network access once.  This is intentional — it exercises the real
# end-user install path.  Subsequent runs reuse the profile's elpa/ and
# are offline.  If vterm's native compilation is a concern on your box,
# set KNAYAWP_TERMINAL_BACKEND=eat (pure elisp, no C toolchain needed).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# --- Argument parsing ------------------------------------------------------
# Flags starting with "-" are collected; the first non-flag is PROJECT_PATH.
# -nw is forwarded to emacsclient for a terminal frame.  --no-layout skips
# the knayawp-layout-setup eval on attach.
nw_flag=""
run_layout=1
project_path=""
for arg in "$@"; do
  case "$arg" in
    -nw)
      nw_flag="-nw"
      ;;
    --no-layout)
      run_layout=0
      ;;
    -*)
      echo "run-dogfood.sh: unknown flag: $arg" >&2
      exit 1
      ;;
    *)
      if [[ -n "$project_path" ]]; then
        echo "run-dogfood.sh: only one PROJECT_PATH may be given (extra: $arg)" >&2
        exit 1
      fi
      project_path="$arg"
      ;;
  esac
done

if [[ -z "$project_path" ]]; then
  echo "run-dogfood.sh: PROJECT_PATH is required" >&2
  echo "Usage: ./test/run-dogfood.sh [-nw] [--no-layout] PROJECT_PATH" >&2
  exit 1
fi

if [[ ! -d "$project_path" ]]; then
  echo "run-dogfood.sh: not a directory: $project_path" >&2
  exit 1
fi

# Resolve to an absolute path so the frame opens the right project
# regardless of the caller's cwd.
project_path="$(cd "$project_path" && pwd)"

# --- Slug + daemon name derivation ----------------------------------------
# Mirror knayawp-editor-server-name's default: take the basename and
# sanitize to a safe token; prepend "knayawp-".  The daemon/server name is
# "knayawp-<project>" per ADR-006.
project_basename="$(basename "$project_path")"
project_slug="$(printf '%s' "$project_basename" | tr -c 'A-Za-z0-9._-' '-')"
if [[ -z "$project_slug" ]]; then
  echo "run-dogfood.sh: could not derive a slug from: $project_path" >&2
  exit 1
fi
server_name="knayawp-${project_slug}"

# --- Profile directory -----------------------------------------------------
dogfood_home="${KNAYAWP_DOGFOOD_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/knayawp-dogfood}"
profile_dir="${dogfood_home}/${project_slug}"
socket_dir="${profile_dir}/server"
mkdir -p "$profile_dir" "$socket_dir"
# The Emacs server refuses a socket in a directory accessible by others.
chmod 700 "$socket_dir"

terminal_backend="${KNAYAWP_TERMINAL_BACKEND:-vterm}"

# --- Generate the minimal profile init.el ---------------------------------
# Regenerated on every run so re-running always reflects the latest checkout
# path and template.  This is the script writing its OWN profile — not a
# bash -c wrapper and not hiding commands.
cat > "${profile_dir}/init.el" <<EOF
;;; init.el --- knayawp dogfood profile for ${project_slug} -*- lexical-binding: t; -*-
;;; Commentary:
;; Generated by test/run-dogfood.sh.  Do not hand-edit — regenerated on every
;; run.  Installs knayawp from a local checkout the same way an end user would
;; (package-vc-install-from-checkout: real autoloads + byte-compile).
;;; Code:

;; Isolate the per-profile server socket so concurrent project daemons never
;; collide (complements the per-daemon --daemon=NAME identity; see ADR-006).
(setq server-socket-dir "${socket_dir}")

;; Bootstrap package.el with GNU ELPA + MELPA so knayawp's dependencies
;; (magit and the terminal backend) can install on first run.
(require 'package)
(setq package-archives
      '(("gnu"   . "https://elpa.gnu.org/packages/")
        ("melpa" . "https://melpa.org/packages/")))
(package-initialize)
(unless package-archive-contents
  (package-refresh-contents))

;; Install knayawp from THIS checkout through real package machinery.
;; Idempotent: a no-op once the package is registered in this profile.
(unless (package-installed-p 'knayawp)
  (package-vc-install-from-checkout "${REPO_ROOT}" "knayawp"))

(require 'knayawp)
;; Belt-and-suspenders for the non-daemon path (ADR-006): harmless under the
;; daemon model, where branch 1 reuses the daemon's own --daemon=NAME server.
(setq knayawp-editor-server-name "${server_name}")
(setq knayawp-terminal-backend '${terminal_backend})
(knayawp-mode 1)

(provide 'init)
;;; init.el ends here
EOF

# The profile's init.el sets server-socket-dir to the profile's own
# server/ dir, so the daemon's socket lives at <socket_dir>/<server_name>
# rather than the default location.  emacsclient's -s accepts an absolute
# socket PATH, so we address the daemon by that path everywhere below.
socket_path="${socket_dir}/${server_name}"

# --- Start daemon (if not already running) + attach a frame ---------------
# Probe for a live daemon via its socket path.  --eval against a live server
# returns 0; a missing socket makes emacsclient exit non-zero.
if emacsclient -s "$socket_path" --eval 't' >/dev/null 2>&1; then
  echo "run-dogfood.sh: daemon '$server_name' already running — attaching a new frame"
else
  echo "run-dogfood.sh: starting daemon '$server_name' (profile: $profile_dir)"
  echo "run-dogfood.sh: first run installs deps from ELPA/MELPA — needs network"
  emacs -q --init-directory="$profile_dir" -l "${profile_dir}/init.el" \
        --daemon="$server_name"
fi

# Build the emacsclient attach command.
client_args=(-s "$socket_path")
if [[ -n "$nw_flag" ]]; then
  client_args+=("$nw_flag")
else
  client_args+=(-c)
fi
if [[ "$run_layout" -eq 1 ]]; then
  client_args+=(--eval "(progn (find-file \"${project_path}\") (knayawp-layout-setup))")
else
  client_args+=("$project_path")
fi

echo "run-dogfood.sh: attaching frame to '$server_name' (project: $project_path)"
exec emacsclient "${client_args[@]}"
