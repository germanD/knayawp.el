;;; copy-mode-toggle.el --- Probe for copy-mode toggle (issue #118) -*- lexical-binding: t; -*-

;;; Commentary:

;; Three-scenario probe for `knayawp-terminal-copy-mode' toggling.
;; Run via:
;;   test/run-probe.sh test/probes/copy-mode-toggle.el
;;
;; Scenario 1 — Enter from editor dispatch: editor is selected, invoke
;;   `knayawp-terminal-copy-mode', verify focus moved to the vterm
;;   panel (slot 0) and `vterm-copy-mode' is active in that buffer.
;;
;; Scenario 2 — Exit from editor dispatch (the bug-118 toggle fix):
;;   enter copy mode once (as S1), then invoke a second time; verify
;;   `vterm-copy-mode' is now nil in the terminal buffer.
;;
;; Scenario 3 — Toggle from within the terminal panel: select the
;;   vterm panel directly, enter copy mode, verify active; call again,
;;   verify inactive.
;;
;; All three scenarios require a real vterm buffer, so vterm must be
;; compiled.  If the terminal panel cannot be found, each scenario
;; aborts with a descriptive message rather than crashing.
;;
;; Note on window counts: `test/sandbox.el' opens a `*knayawp-sandbox*'
;; help window.  All total-window counts include it:
;;   Full layout: 3 panels + editor + sandbox helper = 5 windows.

;;; Code:

(require 'cl-lib)
(require 'seq)

;;;; Helpers

(defun copy-mode--settle ()
  "Pump the event loop briefly to let timers and redraws settle."
  (sit-for 0.3))

(defun copy-mode--setup-layout ()
  "Activate `knayawp-mode' and create a fresh layout."
  (knayawp-mode 1)
  (setq knayawp-magit-commit-style 'off)
  (setq knayawp--zoomed-panel nil)
  (knayawp-layout-setup)
  (copy-mode--settle))

(defun copy-mode--teardown-layout ()
  "Tear down the knayawp layout."
  (when (frame-parameter nil 'knayawp--monocle-config)
    (knayawp-monocle-panel)
    (copy-mode--settle))
  (knayawp-layout-teardown)
  (knayawp-mode -1)
  (copy-mode--settle))

(defun copy-mode--vterm-buffer ()
  "Return the buffer in the vterm panel (slot 0), or nil."
  (let ((win (knayawp--side-window-for-slot 0)))
    (and win (window-buffer win))))

(defun copy-mode--vterm-copy-mode-active-p (buf)
  "Return non-nil if `vterm-copy-mode' is active in BUF."
  (and buf (buffer-live-p buf)
       (buffer-local-value 'vterm-copy-mode buf)))

;;;; Scenario 1: Enter copy mode from the editor

(defun copy-mode--scenario-1 ()
  "Scenario 1 — invoke from editor, verify entry into copy mode."
  (knayawp-probe-section "SCENARIO 1 -- enter copy mode from editor dispatch")
  (condition-case e
      (let ((default-directory (file-name-as-directory sandbox--test-dir)))
        (copy-mode--setup-layout)
        (let ((term-buf (copy-mode--vterm-buffer)))
          (unless term-buf
            (knayawp-probe-abort "s1: no vterm buffer at slot 0"))
          (knayawp-probe-log "  vterm buffer: %S" (buffer-name term-buf))
          ;; Start from the editor (non-side) window.
          (knayawp-select-editor)
          (knayawp-probe-check "s1-editor-selected" nil
                               (window-parameter (selected-window) 'window-side))
          ;; First invocation should enter copy mode.
          (knayawp-terminal-copy-mode)
          (copy-mode--settle)
          ;; Focus must have moved to the terminal panel.
          (knayawp-probe-check "s1-focus-in-terminal" 'right
                               (window-parameter (selected-window) 'window-side))
          (knayawp-probe-check "s1-focus-at-slot-0" 0
                               (window-parameter (selected-window) 'window-slot))
          ;; vterm-copy-mode must be active in the terminal buffer.
          (knayawp-probe-check "s1-copy-mode-active" t
                               (not (null (copy-mode--vterm-copy-mode-active-p term-buf)))
                               #'eq)
          ;; Exit copy mode so teardown starts from a clean state.
          (knayawp-terminal-copy-mode)
          (copy-mode--settle)))
    (error (knayawp-probe-abort "s1 failed: %S" e)))
  (copy-mode--teardown-layout))

;;;; Scenario 2: Toggle off from editor dispatch (the bug-118 fix)

(defun copy-mode--scenario-2 ()
  "Scenario 2 — second invocation exits copy mode."
  (knayawp-probe-section "SCENARIO 2 -- second invocation exits copy mode (bug-118)")
  (condition-case e
      (let ((default-directory (file-name-as-directory sandbox--test-dir)))
        (copy-mode--setup-layout)
        (let ((term-buf (copy-mode--vterm-buffer)))
          (unless term-buf
            (knayawp-probe-abort "s2: no vterm buffer at slot 0"))
          ;; Enter copy mode.
          (knayawp-select-editor)
          (knayawp-terminal-copy-mode)
          (copy-mode--settle)
          (knayawp-probe-check "s2-copy-mode-on" t
                               (not (null (copy-mode--vterm-copy-mode-active-p term-buf)))
                               #'eq)
          ;; Second invocation must exit copy mode.
          (knayawp-terminal-copy-mode)
          (copy-mode--settle)
          (knayawp-probe-check "s2-copy-mode-off" nil
                               (copy-mode--vterm-copy-mode-active-p term-buf))
          ;; Window focus stays on the terminal panel — we did not jump away.
          (knayawp-probe-check "s2-still-in-terminal" 'right
                               (window-parameter (selected-window) 'window-side))))
    (error (knayawp-probe-abort "s2 failed: %S" e)))
  (copy-mode--teardown-layout))

;;;; Scenario 3: Toggle from within the terminal panel

(defun copy-mode--scenario-3 ()
  "Scenario 3 — toggle from inside the terminal panel."
  (knayawp-probe-section "SCENARIO 3 -- toggle directly from terminal panel")
  (condition-case e
      (let ((default-directory (file-name-as-directory sandbox--test-dir)))
        (copy-mode--setup-layout)
        (let ((term-buf (copy-mode--vterm-buffer)))
          (unless term-buf
            (knayawp-probe-abort "s3: no vterm buffer at slot 0"))
          ;; Select the vterm panel directly.
          (let ((win (knayawp--side-window-for-slot 0)))
            (select-window win))
          (knayawp-probe-check "s3-pre-copy-mode-off" nil
                               (copy-mode--vterm-copy-mode-active-p term-buf))
          ;; Enter copy mode.
          (knayawp-terminal-copy-mode)
          (copy-mode--settle)
          (knayawp-probe-check "s3-copy-mode-on" t
                               (not (null (copy-mode--vterm-copy-mode-active-p term-buf)))
                               #'eq)
          ;; Exit copy mode.
          (knayawp-terminal-copy-mode)
          (copy-mode--settle)
          (knayawp-probe-check "s3-copy-mode-off" nil
                               (copy-mode--vterm-copy-mode-active-p term-buf))
          ;; Layout should be intact — no windows were destroyed.
          (knayawp-probe-check "s3-layout-intact" 5
                               (length (window-list nil 'nomini)))))
    (error (knayawp-probe-abort "s3 failed: %S" e)))
  (copy-mode--teardown-layout))

;;;; Drive all scenarios

(knayawp-probe-watchdog 90)

(condition-case e
    (let ((default-directory (file-name-as-directory sandbox--test-dir)))
      (knayawp-probe-log "  probe start  default-directory=%S" default-directory)
      (copy-mode--scenario-1)
      (copy-mode--scenario-2)
      (copy-mode--scenario-3))
  (error (knayawp-probe-abort "top-level error: %S" e)))

(knayawp-probe-finish)

;;; copy-mode-toggle.el ends here
