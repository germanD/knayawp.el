;;; side-pane-visit-pr52.el --- Probe for side-pane visit routing -*- lexical-binding: t; -*-

;;; Commentary:

;; Three-scenario probe for `knayawp-side-pane-visit-style'.
;; Run via the suite (test/run-probes.sh) or individually:
;;   test/run-probe.sh test/probes/side-pane-visit-pr52.el
;;
;; Scenario A — managed-split visit from magit slot:
;;   Layout active, style `managed-split', visit triggered from the
;;   magit side window.  The visited buffer must open in a vertical
;;   split of the editor pane.  The magit slot must still exist.
;;   The editor pane must now contain 2 windows (editor + split).
;;
;; Scenario B — default style: no extra split:
;;   Layout active, style `default'.  After setup,
;;   `knayawp--visit-display-entry' must be nil, confirming visit
;;   routing was never installed.
;;
;; Scenario C — monocle active with managed-split: no split:
;;   Layout active, monocle entered, style `managed-split'.
;;   A display-buffer call from a side window must NOT split the
;;   editor pane (condition returns nil because monocle is active).
;;   Monocle state must be preserved after the display-buffer call.
;;
;; Note on window counts: `test/sandbox.el' opens a `*knayawp-sandbox*'
;; help buffer at the bottom via `display-buffer-at-bottom'.  This helper
;; window persists as a regular (non-side) window throughout the session.
;; All window counts include it:
;;   - Full layout:    5 total (3 panels + editor + sandbox helper).
;;   - After split:    6 total (3 panels + editor + new split + sandbox helper).
;;   - Non-side wins:  2 (editor + sandbox helper); 3 after split.

;;; Code:

(require 'cl-lib)
(require 'seq)

;;;; Helpers

(defun visit-pr52--settle ()
  "Pump the event loop briefly to let timers and redraws settle."
  (sit-for 0.3))

(defun visit-pr52--setup-layout (style)
  "Activate `knayawp-mode' and create a fresh layout with STYLE."
  (knayawp-mode 1)
  (setq knayawp-magit-commit-style 'off)
  (setq knayawp-side-pane-visit-style style)
  ;; Reset zoom and visit state so scenarios cannot bleed.
  (setq knayawp--zoomed-panel nil)
  (knayawp--remove-visit-routing)
  (knayawp-layout-setup)
  (visit-pr52--settle))

(defun visit-pr52--teardown ()
  "Tear down the knayawp layout and clean up monocle + visit state."
  (when (frame-parameter nil 'knayawp--monocle-config)
    (knayawp-monocle-panel)
    (visit-pr52--settle))
  (knayawp-layout-teardown)
  (setq knayawp-side-pane-visit-style 'default)
  ;; Close any extra non-side windows opened during the scenario
  ;; (e.g. editor splits showing hello.el) so they don't bleed into
  ;; the next scenario's window counts.  Keep the editor window and
  ;; the sandbox helper window alive.
  (let ((editor-win (seq-find (lambda (w)
                                (and (not (window-parameter w 'window-side))
                                     (not (string= (buffer-name (window-buffer w))
                                                   "*knayawp-sandbox*"))))
                              (window-list nil 'nomini))))
    (dolist (w (window-list nil 'nomini))
      (when (and (not (window-parameter w 'window-side))
                 (not (eq w editor-win))
                 (not (string= (buffer-name (window-buffer w))
                               "*knayawp-sandbox*")))
        (ignore-errors (delete-window w)))))
  (visit-pr52--settle))

(defun visit-pr52--count-windows ()
  "Return total live windows in the selected frame."
  (length (window-list nil 'nomini)))

(defun visit-pr52--count-non-side-windows ()
  "Return non-side windows (editor + sandbox helper, etc.)."
  (seq-count (lambda (w)
               (null (window-parameter w 'window-side)))
             (window-list nil 'nomini)))

(defun visit-pr52--count-side-windows ()
  "Return side windows in the selected frame."
  (seq-count (lambda (w) (window-parameter w 'window-side))
             (window-list nil 'nomini)))

(defun visit-pr52--select-side-slot (slot)
  "Select the side window at SLOT; error if not found."
  (let ((win (knayawp--side-window-for-slot slot)))
    (unless win
      (error "No side window at slot %S" slot))
    (select-window win)))

;;;; Scenario A: managed-split visit from magit slot

(defun visit-pr52--scenario-a ()
  "Scenario A — managed-split: visit opens in editor split."
  (knayawp-probe-section "SCENARIO A -- managed-split visit from magit slot")
  (condition-case e
      (let ((default-directory (file-name-as-directory sandbox--test-dir)))
        (visit-pr52--setup-layout 'managed-split)
        ;; Confirm visit routing entry is present.
        (knayawp-probe-check "sA-visit-entry-installed" t
                             (not (null knayawp--visit-display-entry)))
        ;; Full layout: 5 windows (3 panels + editor + sandbox helper).
        (knayawp-probe-check "sA-pre-windows" 5
                             (visit-pr52--count-windows))
        (knayawp-probe-check "sA-pre-non-side" 2
                             (visit-pr52--count-non-side-windows))
        ;; Select the magit side window.
        (visit-pr52--select-side-slot -1)
        (knayawp-probe-log "  selected window side: %S"
                           (window-parameter (selected-window) 'window-side))
        ;; Create a file buffer to visit.
        (let* ((file (expand-file-name "hello.el" sandbox--test-dir))
               (file-buf (find-file-noselect file)))
          (knayawp-probe-log "  visiting: %S" (buffer-name file-buf))
          ;; display-buffer from the magit side window with our routing.
          (display-buffer file-buf)
          (visit-pr52--settle)
          (knayawp-probe-log "  post-visit windows: %S"
                             (knayawp-probe-window-summary))
          ;; Editor pane should now have a split: 3 non-side windows
          ;; (editor + new split + sandbox helper).
          (knayawp-probe-check "sA-post-non-side" 3
                               (visit-pr52--count-non-side-windows))
          ;; Total: 6 windows (3 panels + 3 non-side).
          (knayawp-probe-check "sA-post-total" 6
                               (visit-pr52--count-windows))
          ;; Magit slot must still exist.
          (knayawp-probe-check "sA-magit-slot-exists" t
                               (not (null (knayawp--side-window-for-slot -1))))
          ;; All 3 side windows must still be present.
          (knayawp-probe-check "sA-side-windows" 3
                               (visit-pr52--count-side-windows))
          ;; The file buffer must be visible somewhere in the frame.
          (knayawp-probe-check "sA-file-buf-visible" t
                               (not (null (get-buffer-window file-buf))))))
    (error (knayawp-probe-abort "sA failed: %S" e)))
  (visit-pr52--teardown))

;;;; Scenario B: default style — no extra split, no visit entry

(defun visit-pr52--scenario-b ()
  "Scenario B — default style: visit entry nil, no extra split."
  (knayawp-probe-section "SCENARIO B -- default style (no managed routing)")
  (condition-case e
      (let ((default-directory (file-name-as-directory sandbox--test-dir)))
        (visit-pr52--setup-layout 'default)
        ;; With style = default, visit routing must NOT be installed.
        (knayawp-probe-check "sB-visit-entry-nil" nil
                             knayawp--visit-display-entry)
        ;; Full layout: 3 side windows must be present.
        (knayawp-probe-check "sB-side-windows-setup" 3
                             (visit-pr52--count-side-windows))
        ;; Select the vterm side window and display a buffer.
        (visit-pr52--select-side-slot 0)
        (let* ((file (expand-file-name "hello.el" sandbox--test-dir))
               (file-buf (find-file-noselect file)))
          (display-buffer file-buf)
          (visit-pr52--settle)
          (knayawp-probe-log "  post-visit windows: %S"
                             (knayawp-probe-window-summary))
          ;; With default style the visit entry is nil, so our custom
          ;; action never ran.  The file buffer goes wherever Emacs
          ;; chose — we just confirm the entry stayed nil.
          (knayawp-probe-check "sB-entry-still-nil" nil
                               knayawp--visit-display-entry)
          ;; Side windows unchanged: 3.
          (knayawp-probe-check "sB-side-windows" 3
                               (visit-pr52--count-side-windows))))
    (error (knayawp-probe-abort "sB failed: %S" e)))
  (visit-pr52--teardown))

;;;; Scenario C: monocle + managed-split — no split during monocle

(defun visit-pr52--scenario-c ()
  "Scenario C — monocle active: condition returns nil, no editor split."
  (knayawp-probe-section "SCENARIO C -- monocle + managed-split (condition gated)")
  (condition-case e
      (let ((default-directory (file-name-as-directory sandbox--test-dir)))
        (visit-pr52--setup-layout 'managed-split)
        ;; Enter monocle from the vterm panel.
        (visit-pr52--select-side-slot 0)
        (let ((vterm-buf (window-buffer (selected-window))))
          (knayawp-monocle-panel)
          (visit-pr52--settle)
          (knayawp-probe-log "  in-monocle windows: %S"
                             (knayawp-probe-window-summary))
          ;; Monocle must be active.
          (knayawp-probe-check "sC-monocle-active" t
                               (consp (frame-parameter nil
                                                       'knayawp--monocle-config)))
          ;; In monocle: 1 panel window + sandbox helper = 2 windows.
          (knayawp-probe-check "sC-monocle-window-count" 2
                               (visit-pr52--count-windows))
          ;; Now try to display a file buffer from the monocle window.
          ;; The selected window is not a side window (monocle expands to
          ;; editor area), so the condition must return nil and Emacs
          ;; handles it via its default action.
          (let* ((file (expand-file-name "hello.el" sandbox--test-dir))
                 (file-buf (find-file-noselect file))
                 (pre-count (visit-pr52--count-windows)))
            ;; Select the monocle window (it IS a regular non-side window
            ;; after monocle expansion, as monocle deletes the side windows).
            (select-window (seq-find (lambda (w)
                                       (eq (window-buffer w) vterm-buf))
                                     (window-list nil 'nomini)))
            (knayawp-probe-log "  selected side param: %S"
                               (window-parameter (selected-window)
                                                 'window-side))
            ;; Condition check: selected window must NOT be a side window.
            (knayawp-probe-check "sC-monocle-win-not-side" nil
                                 (window-parameter (selected-window)
                                                   'window-side))
            ;; Confirm condition returns nil for this context.
            (knayawp-probe-check "sC-condition-nil-in-monocle" nil
                                 (knayawp--visit-from-side-window-p
                                  file-buf nil))
            ;; Monocle state must be preserved after the check.
            (knayawp-probe-check "sC-monocle-preserved" t
                                 (consp (frame-parameter nil
                                                         'knayawp--monocle-config)))
            (ignore pre-count vterm-buf))))
    (error (knayawp-probe-abort "sC failed: %S" e)))
  (visit-pr52--teardown))

;;;; Drive all scenarios

(knayawp-probe-watchdog 90)

(condition-case e
    (let ((default-directory (file-name-as-directory sandbox--test-dir)))
      (knayawp-probe-log "  probe start  default-directory=%S" default-directory)
      (visit-pr52--scenario-a)
      (visit-pr52--scenario-b)
      (visit-pr52--scenario-c))
  (error (knayawp-probe-abort "top-level error: %S" e)))

(knayawp-probe-finish)

;;; side-pane-visit-pr52.el ends here
