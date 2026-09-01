;;; theme-refresh-pr101.el --- Probe for theme-refresh hook regressions -*- lexical-binding: t; -*-

;;; Commentary:

;; Five-scenario regression probe for `knayawp--refresh-panels-after-theme'.
;; Run via the suite (test/run-probes.sh) or individually:
;;   test/run-probe.sh test/probes/theme-refresh-pr101.el
;;
;; Covers the 5 correctness bugs fixed in commit 428ffca on
;; feat/vterm-theme-refresh-100 (PR #101 / issue #100):
;;
;; Scenario A — Basic: refresh fires when layout is active.
;;   Setup: call `knayawp-layout-setup'; verify 3 side windows.
;;   Action: call `knayawp--refresh-panels-after-theme'.
;;   Assert: side windows still present (no spurious teardown).
;;
;; Scenario B — Zoom guard: refresh skips when a panel is zoomed.
;;   Setup: layout active; zoom vterm panel (1 side window).
;;   Action: call `knayawp--refresh-panels-after-theme'.
;;   Assert: `knayawp--zoomed-panel' still non-nil (zoom not cleared).
;;   Assert: side-window count unchanged (no re-layout fired).
;;
;; Scenario C — Monocle guard: refresh skips when monocle is active.
;;   Setup: layout active; enter monocle from vterm.
;;   Action: call `knayawp--refresh-panels-after-theme'.
;;   Assert: `knayawp--monocle-config' frame param still set.
;;   Assert: total window count unchanged (monocle not broken).
;;
;; Scenario D — Focus preservation: selected window unchanged after refresh.
;;   Setup: layout active; select the vterm side window.
;;   Action: call `knayawp--refresh-panels-after-theme'.
;;   Assert: selected window is still the vterm side window.
;;
;; Scenario E — No-layout guard: refresh is a no-op without active layout.
;;   Setup: `knayawp-mode' enabled; no `knayawp-layout-setup' call.
;;   Action: call `knayawp--refresh-panels-after-theme'.
;;   Assert: side-window count is still 0 (no layout created).
;;
;; Note on window counts: `test/sandbox.el' opens a `*knayawp-sandbox*'
;; help buffer at the bottom via `display-buffer-at-bottom'.  This helper
;; window persists as a regular (non-side) window throughout the session.
;; All window counts include it:
;;   - Full layout:              5 total (3 panels + editor + sandbox helper).
;;   - Zoom (1 panel + editor):  3 total (2 + sandbox helper).
;;   - Monocle (1 panel):        2 total (panel + sandbox helper).
;;   - No layout:                2 total (editor + sandbox helper).

;;; Code:

(require 'cl-lib)
(require 'seq)

;;;; Helpers

(defun tr--settle ()
  "Pump the event loop briefly to let timers and redraws settle."
  (sit-for 0.3))

(defun tr--setup-layout ()
  "Activate `knayawp-mode' and create a fresh layout.
Must be called with `default-directory' set to the sandbox project."
  (knayawp-mode 1)
  (setq knayawp-magit-commit-style 'off)
  ;; Reset zoom/monocle state so scenarios cannot bleed into each other.
  (setq knayawp--zoomed-panel nil)
  (set-frame-parameter nil 'knayawp--monocle-config nil)
  (knayawp-layout-setup)
  (tr--settle))

(defun tr--teardown-layout ()
  "Tear down the layout and clear any leftover zoom/monocle state."
  ;; Exit monocle first if active, so teardown sees the full layout.
  (when (frame-parameter nil 'knayawp--monocle-config)
    (knayawp-monocle-panel)
    (tr--settle))
  ;; Restore zoomed layout so teardown can remove all side windows.
  (when knayawp--zoomed-panel
    (knayawp-zoom-panel)
    (tr--settle))
  (knayawp-layout-teardown)
  (setq knayawp--zoomed-panel nil)
  (set-frame-parameter nil 'knayawp--monocle-config nil)
  (tr--settle))

(defun tr--side-window-count ()
  "Return the count of side windows in the selected frame."
  (length (knayawp-probe-side-windows)))

(defun tr--total-window-count ()
  "Return the total number of live windows in the selected frame."
  (length (window-list nil 'nomini)))

(defun tr--select-side-slot (slot)
  "Select the side window at SLOT; signal error if not found."
  (let ((win (knayawp--side-window-for-slot slot)))
    (unless win
      (error "No side window at slot %S" slot))
    (select-window win)))

;;;; Scenario A: Basic — refresh fires when layout is active

(defun tr--scenario-a ()
  "Scenario A — refresh fires and preserves side windows."
  (knayawp-probe-section "SCENARIO A -- basic: refresh fires with active layout")
  (condition-case e
      (let ((default-directory (file-name-as-directory sandbox--test-dir)))
        (tr--setup-layout)
        (knayawp-probe-log "  pre-refresh windows: %S"
                           (knayawp-probe-window-summary))
        ;; Sanity: 3 side windows before calling the hook.
        (knayawp-probe-check "sA-pre-side-wins" 3
                             (tr--side-window-count))
        ;; Invoke the theme hook directly.
        (knayawp--refresh-panels-after-theme 'modus-vivendi)
        (tr--settle)
        (knayawp-probe-log "  post-refresh windows: %S"
                           (knayawp-probe-window-summary))
        ;; Side windows must still be present — no spurious teardown.
        (knayawp-probe-check "sA-post-side-wins" 3
                             (tr--side-window-count))
        ;; Full window count: 3 panels + editor + sandbox helper = 5.
        (knayawp-probe-check "sA-post-total-wins" 5
                             (tr--total-window-count)))
    (error (knayawp-probe-abort "sA failed: %S" e)))
  (tr--teardown-layout))

;;;; Scenario B: Zoom guard — refresh skips when a panel is zoomed

(defun tr--scenario-b ()
  "Scenario B — refresh is a no-op while a panel is zoomed."
  (knayawp-probe-section "SCENARIO B -- zoom guard: refresh skips when zoomed")
  (condition-case e
      (let ((default-directory (file-name-as-directory sandbox--test-dir)))
        (tr--setup-layout)
        ;; Zoom the vterm panel (slot 0).
        (tr--select-side-slot 0)
        (knayawp-zoom-panel)
        (tr--settle)
        (knayawp-probe-log "  after zoom windows: %S"
                           (knayawp-probe-window-summary))
        ;; Sanity: zoom is active, 1 side window (vterm) + editor + sandbox = 3.
        (knayawp-probe-check "sB-zoomed" t
                             (not (null knayawp--zoomed-panel)))
        (knayawp-probe-check "sB-pre-side-wins" 1
                             (tr--side-window-count))
        (let ((side-count-before (tr--side-window-count))
              (zoom-before knayawp--zoomed-panel))
          ;; Invoke the theme hook — must be a no-op.
          (knayawp--refresh-panels-after-theme 'modus-vivendi)
          (tr--settle)
          (knayawp-probe-log "  post-refresh windows: %S"
                             (knayawp-probe-window-summary))
          ;; Zoom state must be preserved (not cleared).
          (knayawp-probe-check "sB-zoom-preserved" zoom-before
                               knayawp--zoomed-panel)
          ;; Side-window count must not have changed.
          (knayawp-probe-check "sB-side-wins-unchanged" side-count-before
                               (tr--side-window-count))))
    (error (knayawp-probe-abort "sB failed: %S" e)))
  (tr--teardown-layout))

;;;; Scenario C: Monocle guard — refresh skips when monocle is active

(defun tr--scenario-c ()
  "Scenario C — refresh is a no-op while monocle is active."
  (knayawp-probe-section "SCENARIO C -- monocle guard: refresh skips in monocle")
  (condition-case e
      (let ((default-directory (file-name-as-directory sandbox--test-dir)))
        (tr--setup-layout)
        ;; Enter monocle from the vterm side window.
        (tr--select-side-slot 0)
        (knayawp-monocle-panel)
        (tr--settle)
        (knayawp-probe-log "  after monocle windows: %S"
                           (knayawp-probe-window-summary))
        ;; Sanity: monocle active — 1 window + sandbox helper = 2.
        (knayawp-probe-check "sC-monocle-set" t
                             (consp (frame-parameter nil
                                                    'knayawp--monocle-config)))
        (let ((total-before (tr--total-window-count)))
          ;; Invoke the theme hook — must be a no-op.
          (knayawp--refresh-panels-after-theme 'modus-vivendi)
          (tr--settle)
          (knayawp-probe-log "  post-refresh windows: %S"
                             (knayawp-probe-window-summary))
          ;; Monocle frame parameter must still be set.
          (knayawp-probe-check "sC-monocle-preserved" t
                               (consp (frame-parameter nil
                                                      'knayawp--monocle-config)))
          ;; Total window count must not have changed.
          (knayawp-probe-check "sC-total-wins-unchanged" total-before
                               (tr--total-window-count))))
    (error (knayawp-probe-abort "sC failed: %S" e)))
  (tr--teardown-layout))

;;;; Scenario D: Focus preservation — selected window unchanged after refresh

(defun tr--scenario-d ()
  "Scenario D — selected window is preserved across a refresh.
`force-window-update' does not destroy or recreate window objects,
so the selected window remains the same live object after the refresh."
  (knayawp-probe-section "SCENARIO D -- focus: selected window unchanged after refresh")
  (condition-case e
      (let ((default-directory (file-name-as-directory sandbox--test-dir)))
        (tr--setup-layout)
        ;; Select the vterm side window (slot 0).
        (tr--select-side-slot 0)
        (tr--settle)
        (let ((vterm-buf (window-buffer (selected-window))))
          (knayawp-probe-log "  selected before: slot=0 buffer=%S"
                             (buffer-name vterm-buf))
          ;; Invoke the theme hook.
          (knayawp--refresh-panels-after-theme 'modus-vivendi)
          (tr--settle)
          (let ((sel-buf (window-buffer (selected-window)))
                (sel-slot (window-parameter (selected-window) 'window-slot))
                (sel-side (window-parameter (selected-window) 'window-side)))
            (knayawp-probe-log "  selected after:  buffer=%S side=%S slot=%S"
                               (buffer-name sel-buf) sel-side sel-slot)
            ;; The selected window must be in a side window at slot 0.
            (knayawp-probe-check "sD-still-side" 'right sel-side)
            (knayawp-probe-check "sD-still-slot-0" 0 sel-slot)
            ;; The window must still show the vterm buffer.
            (knayawp-probe-check "sD-buf-unchanged" t
                                 (eq sel-buf vterm-buf)))))
    (error (knayawp-probe-abort "sD failed: %S" e)))
  (tr--teardown-layout))

;;;; Scenario E: No-layout guard — refresh is a no-op without active layout

(defun tr--scenario-e ()
  "Scenario E — refresh is a no-op when no layout has been set up."
  (knayawp-probe-section "SCENARIO E -- no-layout guard: no-op without layout")
  (condition-case e
      (let ((default-directory (file-name-as-directory sandbox--test-dir)))
        ;; Enable mode but do NOT call knayawp-layout-setup.
        (knayawp-mode 1)
        (setq knayawp--zoomed-panel nil)
        (set-frame-parameter nil 'knayawp--monocle-config nil)
        ;; Ensure no active layout for this project root.
        (knayawp-probe-log "  active-layouts: %S" knayawp--active-layouts)
        (knayawp-probe-check "sE-no-active-layout" nil
                             (alist-get
                              (expand-file-name sandbox--test-dir)
                              knayawp--active-layouts nil nil #'equal))
        (knayawp-probe-check "sE-pre-side-wins" 0
                             (tr--side-window-count))
        ;; Invoke the theme hook — must be a no-op.
        (knayawp--refresh-panels-after-theme 'modus-vivendi)
        (tr--settle)
        ;; No side windows must have appeared.
        (knayawp-probe-check "sE-post-side-wins" 0
                             (tr--side-window-count)))
    (error (knayawp-probe-abort "sE failed: %S" e))))

;;;; Drive all scenarios

(knayawp-probe-watchdog 90)

(condition-case e
    (let ((default-directory (file-name-as-directory sandbox--test-dir)))
      (knayawp-probe-log "  probe start  default-directory=%S" default-directory)
      (tr--scenario-a)
      (tr--scenario-b)
      (tr--scenario-c)
      (tr--scenario-d)
      (tr--scenario-e))
  (error (knayawp-probe-abort "top-level error: %S" e)))

(knayawp-probe-finish)

;;; theme-refresh-pr101.el ends here
