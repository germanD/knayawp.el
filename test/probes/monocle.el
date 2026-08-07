;;; monocle.el --- Probe for knayawp-monocle-panel scenarios -*- lexical-binding: t; -*-

;;; Commentary:

;; Six-scenario probe for `knayawp-monocle-panel'.  Run via the suite
;; (test/run-probes.sh) or individually:
;;   test/run-probe.sh test/probes/monocle.el
;;
;; Scenario 1 — Enter from slot 0 (vterm): select the vterm side window,
;;   invoke monocle, verify exactly 1 window (showing vterm buffer), exit,
;;   verify full layout (3 panels + editor + sandbox helper = 5 windows).
;;
;; Scenario 2 — Enter from slot -1 (magit): same as S1 from the magit panel.
;;
;; Scenario 3 — Enter from slot 1 (claude): same as S1 from the claude panel.
;;
;; Scenario 4 — Enter from editor pane: focus is in the editor, invoke monocle,
;;   verify 1 window (editor), exit, verify full layout.
;;
;; Scenario 5 — Monocle + teardown: enter monocle, call teardown, verify
;;   the `knayawp--monocle-config' frame parameter is nil.
;;
;; Scenario 6 — Zoom + monocle round-trip: zoom a panel, enter monocle,
;;   exit monocle, verify zoom state is restored (2 windows: zoomed panel
;;   + editor; +1 sandbox helper = 3).
;;
;; Note on window counts: `test/sandbox.el' opens a `*knayawp-sandbox*'
;; help buffer at the bottom via `display-buffer-at-bottom'.  This helper
;; window persists as a regular (non-side) window throughout the session.
;; All window counts include it:
;;   - In monocle (1 panel):  2 total (panel + sandbox helper).
;;   - Full layout:           5 total (3 panels + editor + sandbox helper).
;;   - Zoom (1 panel + editor): 3 total (2 + sandbox helper).

;;; Code:

(require 'cl-lib)
(require 'seq)

;;;; Helpers

(defun monocle--settle ()
  "Pump the event loop briefly to let timers and redraws settle."
  (sit-for 0.3))

(defun monocle--setup-layout ()
  "Activate `knayawp-mode' and create a fresh layout.
Must be called with `default-directory' set to the sandbox project."
  (knayawp-mode 1)
  (setq knayawp-magit-commit-style 'off)
  (knayawp-layout-setup)
  (monocle--settle))

(defun monocle--count-non-sandbox-windows ()
  "Return the number of live windows in the selected frame."
  (length (window-list nil 'nomini)))

(defun monocle--side-window-count ()
  "Return the count of side windows in the selected frame."
  (length (knayawp-probe-side-windows)))

(defun monocle--teardown-layout ()
  "Tear down the knayawp layout and clear monocle state."
  (when (frame-parameter nil 'knayawp--monocle-config)
    (knayawp-monocle-panel)
    (monocle--settle))
  (knayawp-layout-teardown)
  (monocle--settle))

(defun monocle--select-side-slot (slot)
  "Select the side window at SLOT; signal error if not found."
  (let ((win (knayawp--side-window-for-slot slot)))
    (unless win
      (error "No side window at slot %S" slot))
    (select-window win)))

;;;; Scenario 1: Enter monocle from vterm (slot 0)

(defun monocle--scenario-1 ()
  "Scenario 1 — enter and exit monocle from the vterm panel."
  (knayawp-probe-section "SCENARIO 1 -- enter monocle from vterm (slot 0)")
  (condition-case e
      (let ((default-directory (file-name-as-directory sandbox--test-dir)))
        (monocle--setup-layout)
        ;; Select the vterm side window (slot 0).
        (monocle--select-side-slot 0)
        (let ((vterm-buf (window-buffer (selected-window))))
          (knayawp-probe-log "  pre-monocle windows: %S"
                             (knayawp-probe-window-summary))
          ;; Enter monocle.
          (knayawp-monocle-panel)
          (monocle--settle)
          (knayawp-probe-log "  in-monocle windows: %S"
                             (knayawp-probe-window-summary))
          ;; 1 panel + sandbox helper = 2 windows.
          (knayawp-probe-check "s1-monocle-window-count" 2
                               (monocle--count-non-sandbox-windows))
          ;; That window must show the vterm buffer.
          (knayawp-probe-check "s1-monocle-shows-vterm" t
                               (eq (window-buffer (selected-window)) vterm-buf))
          ;; No side windows remain.
          (knayawp-probe-check "s1-monocle-no-side-wins" 0
                               (monocle--side-window-count))
          ;; monocle-config frame parameter must be set.
          (knayawp-probe-check "s1-monocle-config-set" t
                               (consp (frame-parameter nil
                                                       'knayawp--monocle-config)))
          ;; Exit monocle.
          (knayawp-monocle-panel)
          (monocle--settle)
          (knayawp-probe-log "  post-monocle windows: %S"
                             (knayawp-probe-window-summary))
          ;; Full layout: 3 panels + editor + sandbox helper = 5.
          (knayawp-probe-check "s1-restored-window-count" 5
                               (monocle--count-non-sandbox-windows))
          (knayawp-probe-check "s1-restored-side-wins" 3
                               (monocle--side-window-count))
          ;; monocle-config must be cleared.
          (knayawp-probe-check "s1-monocle-config-nil" nil
                               (frame-parameter nil 'knayawp--monocle-config))))
    (error (knayawp-probe-abort "s1 failed: %S" e)))
  (monocle--teardown-layout))

;;;; Scenario 2: Enter monocle from magit (slot -1)

(defun monocle--scenario-2 ()
  "Scenario 2 — enter and exit monocle from the magit panel."
  (knayawp-probe-section "SCENARIO 2 -- enter monocle from magit (slot -1)")
  (condition-case e
      (let ((default-directory (file-name-as-directory sandbox--test-dir)))
        (monocle--setup-layout)
        (monocle--select-side-slot -1)
        (let ((magit-buf (window-buffer (selected-window))))
          (knayawp-probe-log "  pre-monocle windows: %S"
                             (knayawp-probe-window-summary))
          (knayawp-monocle-panel)
          (monocle--settle)
          (knayawp-probe-log "  in-monocle windows: %S"
                             (knayawp-probe-window-summary))
          (knayawp-probe-check "s2-monocle-window-count" 2
                               (monocle--count-non-sandbox-windows))
          (knayawp-probe-check "s2-monocle-shows-magit" t
                               (eq (window-buffer (selected-window)) magit-buf))
          (knayawp-probe-check "s2-monocle-no-side-wins" 0
                               (monocle--side-window-count))
          (knayawp-monocle-panel)
          (monocle--settle)
          (knayawp-probe-log "  post-monocle windows: %S"
                             (knayawp-probe-window-summary))
          (knayawp-probe-check "s2-restored-window-count" 5
                               (monocle--count-non-sandbox-windows))
          (knayawp-probe-check "s2-restored-side-wins" 3
                               (monocle--side-window-count))))
    (error (knayawp-probe-abort "s2 failed: %S" e)))
  (monocle--teardown-layout))

;;;; Scenario 3: Enter monocle from claude (slot 1)

(defun monocle--scenario-3 ()
  "Scenario 3 — enter and exit monocle from the claude panel."
  (knayawp-probe-section "SCENARIO 3 -- enter monocle from claude (slot 1)")
  (condition-case e
      (let ((default-directory (file-name-as-directory sandbox--test-dir)))
        (monocle--setup-layout)
        (monocle--select-side-slot 1)
        (let ((claude-buf (window-buffer (selected-window))))
          (knayawp-probe-log "  pre-monocle windows: %S"
                             (knayawp-probe-window-summary))
          (knayawp-monocle-panel)
          (monocle--settle)
          (knayawp-probe-log "  in-monocle windows: %S"
                             (knayawp-probe-window-summary))
          (knayawp-probe-check "s3-monocle-window-count" 2
                               (monocle--count-non-sandbox-windows))
          (knayawp-probe-check "s3-monocle-shows-claude" t
                               (eq (window-buffer (selected-window)) claude-buf))
          (knayawp-probe-check "s3-monocle-no-side-wins" 0
                               (monocle--side-window-count))
          (knayawp-monocle-panel)
          (monocle--settle)
          (knayawp-probe-log "  post-monocle windows: %S"
                             (knayawp-probe-window-summary))
          (knayawp-probe-check "s3-restored-window-count" 5
                               (monocle--count-non-sandbox-windows))
          (knayawp-probe-check "s3-restored-side-wins" 3
                               (monocle--side-window-count))))
    (error (knayawp-probe-abort "s3 failed: %S" e)))
  (monocle--teardown-layout))

;;;; Scenario 4: Enter monocle from the editor pane

(defun monocle--scenario-4 ()
  "Scenario 4 — enter and exit monocle from the editor pane."
  (knayawp-probe-section "SCENARIO 4 -- enter monocle from editor pane")
  (condition-case e
      (let ((default-directory (file-name-as-directory sandbox--test-dir)))
        (monocle--setup-layout)
        ;; Focus the editor (non-side) window.
        (knayawp-select-editor)
        (knayawp-probe-log "  pre-monocle windows: %S"
                           (knayawp-probe-window-summary))
        (knayawp-probe-check "s4-selected-not-side" nil
                             (window-parameter (selected-window) 'window-side))
        (knayawp-monocle-panel)
        (monocle--settle)
        (knayawp-probe-log "  in-monocle windows: %S"
                           (knayawp-probe-window-summary))
        ;; editor + sandbox helper = 2 windows.
        (knayawp-probe-check "s4-monocle-window-count" 2
                             (monocle--count-non-sandbox-windows))
        (knayawp-probe-check "s4-monocle-no-side-wins" 0
                             (monocle--side-window-count))
        ;; Exit monocle.
        (knayawp-monocle-panel)
        (monocle--settle)
        (knayawp-probe-log "  post-monocle windows: %S"
                           (knayawp-probe-window-summary))
        (knayawp-probe-check "s4-restored-window-count" 5
                             (monocle--count-non-sandbox-windows))
        (knayawp-probe-check "s4-restored-side-wins" 3
                             (monocle--side-window-count)))
    (error (knayawp-probe-abort "s4 failed: %S" e)))
  (monocle--teardown-layout))

;;;; Scenario 5: Monocle + teardown

(defun monocle--scenario-5 ()
  "Scenario 5 — teardown while in monocle clears the frame parameter."
  (knayawp-probe-section "SCENARIO 5 -- monocle + teardown")
  (condition-case e
      (let ((default-directory (file-name-as-directory sandbox--test-dir)))
        (monocle--setup-layout)
        (monocle--select-side-slot 0)
        (knayawp-monocle-panel)
        (monocle--settle)
        (knayawp-probe-log "  in-monocle windows: %S"
                           (knayawp-probe-window-summary))
        (knayawp-probe-check "s5-monocle-config-set" t
                             (consp (frame-parameter nil
                                                     'knayawp--monocle-config)))
        ;; Teardown must clear the monocle frame parameter.
        (knayawp-layout-teardown)
        (monocle--settle)
        (knayawp-probe-check "s5-monocle-config-nil" nil
                             (frame-parameter nil 'knayawp--monocle-config)))
    (error (knayawp-probe-abort "s5 failed: %S" e))))

;;;; Scenario 6: Zoom + monocle round-trip

(defun monocle--scenario-6 ()
  "Scenario 6 — zoom a panel, enter monocle, exit, verify zoom is restored."
  (knayawp-probe-section "SCENARIO 6 -- zoom + monocle round-trip")
  (condition-case e
      (let ((default-directory (file-name-as-directory sandbox--test-dir)))
        (monocle--setup-layout)
        ;; Zoom the vterm panel.
        (monocle--select-side-slot 0)
        (knayawp-zoom-panel)
        (monocle--settle)
        (knayawp-probe-log "  after zoom windows: %S"
                           (knayawp-probe-window-summary))
        (knayawp-probe-check "s6-zoomed-panel" 'vterm knayawp--zoomed-panel)
        ;; 2 windows (zoomed panel + editor) + sandbox helper = 3.
        (knayawp-probe-check "s6-zoom-window-count" 3
                             (monocle--count-non-sandbox-windows))
        ;; Enter monocle.
        (knayawp-monocle-panel)
        (monocle--settle)
        (knayawp-probe-log "  in-monocle windows: %S"
                           (knayawp-probe-window-summary))
        ;; Zoom state cleared by monocle enter.
        (knayawp-probe-check "s6-monocle-clears-zoom" nil
                             knayawp--zoomed-panel)
        ;; 1 panel + sandbox helper = 2 windows.
        (knayawp-probe-check "s6-monocle-window-count" 2
                             (monocle--count-non-sandbox-windows))
        ;; Exit monocle: zoom state must be restored.
        (knayawp-monocle-panel)
        (monocle--settle)
        (knayawp-probe-log "  post-monocle windows: %S"
                           (knayawp-probe-window-summary))
        ;; Zoom state restored to vterm.
        (knayawp-probe-check "s6-zoom-restored" 'vterm knayawp--zoomed-panel)
        ;; Back to 2 windows + sandbox helper = 3.
        (knayawp-probe-check "s6-post-monocle-window-count" 3
                             (monocle--count-non-sandbox-windows))
        (knayawp-probe-check "s6-post-monocle-side-wins" 1
                             (monocle--side-window-count)))
    (error (knayawp-probe-abort "s6 failed: %S" e)))
  (monocle--teardown-layout))

;;;; Drive all scenarios

(knayawp-probe-watchdog 90)

(condition-case e
    (let ((default-directory (file-name-as-directory sandbox--test-dir)))
      (knayawp-probe-log "  probe start  default-directory=%S" default-directory)
      (monocle--scenario-1)
      (monocle--scenario-2)
      (monocle--scenario-3)
      (monocle--scenario-4)
      (monocle--scenario-5)
      (monocle--scenario-6))
  (error (knayawp-probe-abort "top-level error: %S" e)))

(knayawp-probe-finish)

;;; monocle.el ends here
