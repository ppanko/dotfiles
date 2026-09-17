;;; p3-eat-feasibility-test.el --- Eat/Eshell platform gate -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)
(require 'seq)
(require 'eat)
(require 'p3-terminal)
(require 'p3-terminal-test-support)

(defun p3-eat-feasibility-test--fixture-command (exit-code &optional mode)
  "Return the terminal fixture command for EXIT-CODE and optional MODE."
  (let ((fixture (expand-file-name "test/fixtures/p3-terminal-fixture.py"
                                   p3-terminal-test-support-root))
        (python (p3-terminal-test-support-python)))
    (mapconcat #'shell-quote-argument
               (delq nil
                     (list python fixture (number-to-string exit-code) mode))
               " ")))

(defun p3-eat-feasibility-test--eat-child (parent)
  "Return the dedicated Eat visual buffer whose Eshell parent is PARENT."
  (seq-find
   (lambda (buffer)
     (and (buffer-live-p buffer)
          (with-current-buffer buffer
            (and (derived-mode-p 'eat-mode)
                 (boundp 'eshell-parent-buffer)
                 (eq eshell-parent-buffer parent)))))
   (buffer-list)))

(defun p3-eat-feasibility-test--wait-for-eat-child (parent)
  "Wait for and return PARENT's dedicated Eat visual child."
  (let ((deadline (+ (float-time) 5.0))
        child)
    (while (and (not (setq child (p3-eat-feasibility-test--eat-child parent)))
                (< (float-time) deadline))
      (accept-process-output nil 0.05))
    (should (buffer-live-p child))
    child))

(defun p3-eat-feasibility-test--wait-for-text (buffer regexp)
  "Wait for REGEXP to appear in BUFFER."
  (let ((deadline (+ (float-time) 5.0))
        found)
    (while (and (buffer-live-p buffer)
                (not found)
                (< (float-time) deadline))
      (accept-process-output (get-buffer-process buffer) 0.05)
      (with-current-buffer buffer
        (save-excursion
          (goto-char (point-min))
          (setq found (re-search-forward regexp nil t)))))
    (should found)))

(defun p3-eat-feasibility-test--wait-for-process-exit (buffer)
  "Wait for BUFFER's process to exit."
  (let ((deadline (+ (float-time) 5.0)))
    (while (and (buffer-live-p buffer)
                (when-let ((process (get-buffer-process buffer)))
                  (process-live-p process))
                (< (float-time) deadline))
      (accept-process-output (get-buffer-process buffer) 0.05))
    (when (buffer-live-p buffer)
      (should-not (when-let ((process (get-buffer-process buffer)))
                    (process-live-p process))))))

(defun p3-eat-feasibility-test--run-command (buffer command regexp)
  "Run ordinary COMMAND in Eshell BUFFER and require REGEXP in its output."
  (with-current-buffer buffer
    (let ((start (point-max))
          (deadline (+ (float-time) 10.0))
          found)
      (goto-char (point-max))
      (insert command)
      (eshell-send-input)
      (while (and (not found) (< (float-time) deadline))
        (if-let ((process (eshell-head-process)))
            (accept-process-output process 0.05)
          (accept-process-output nil 0.05))
        (save-excursion
          (goto-char start)
          (setq found (re-search-forward regexp nil t))))
      (should found))))

(defun p3-eat-feasibility-test--start-visual-fixture (parent exit-code &optional mode)
  "Run the terminal fixture visually from PARENT and return its Eat child."
  (let* ((python (p3-terminal-test-support-python))
         (program (file-name-nondirectory python)))
    (with-current-buffer parent
      ;; The deterministic Python fixture stands in for Codex/pacman in CI.
      ;; Add only its executable basename to this managed shell's visual table.
      (cl-pushnew program eshell-visual-commands :test #'equal)
      (goto-char (point-max))
      (insert (p3-eat-feasibility-test--fixture-command exit-code mode))
      (eshell-send-input))
    (p3-eat-feasibility-test--wait-for-eat-child parent)))

(defun p3-eat-feasibility-test--assert-terminal-metadata (buffer)
  "Require BUFFER to show a real terminal with nonzero dimensions."
  (with-current-buffer buffer
    (save-excursion
      (goto-char (point-min))
      (should (re-search-forward "__P3_TTY__1:1" nil t))
      (goto-char (point-min))
      (should (re-search-forward
               "__P3_SIZE__\\([1-9][0-9]*\\):\\([1-9][0-9]*\\)" nil t))
      (goto-char (point-min))
      (should-not (search-forward "\033[" nil t)))))

(ert-deftest p3-eat-feasibility-dedicated-visual-buffer-isolates-terminal-output ()
  (when (eq system-type 'windows-nt)
    (ert-skip "Native Windows full-screen TUI/PTY behavior is out of scope"))
  (p3-terminal-test-support-prepare-platform)
  (let ((root (file-name-as-directory temporary-file-directory))
        (p3/project-shell-buffers (make-hash-table :test #'equal))
        parent child)
    (unwind-protect
        (cl-letf (((symbol-function 'p3/project-shell-root) (lambda () root)))
          (eat-eshell-visual-command-mode 1)
          (add-hook 'eat-exec-hook #'p3/project-shell-eat-visual-buffer-setup)
          (setq parent (p3/project-shell-buffer))
          ;; Nonzero exit deliberately leaves the Eat child available for
          ;; inspection; successful-exit cleanup is tested separately.
          (setq child
                (p3-eat-feasibility-test--start-visual-fixture parent 7))
          (should-not (eq child parent))
          (with-current-buffer child
            (should (derived-mode-p 'eat-mode))
            (should (eq (key-binding (kbd "C-y")) #'eat-yank))
            (should (eq (key-binding [xterm-paste]) #'eat-xterm-paste)))
          (p3-eat-feasibility-test--wait-for-text child "__P3_CURSOR__")
          (process-send-string (get-buffer-process child) "x")
          (p3-eat-feasibility-test--wait-for-process-exit child)
          (p3-eat-feasibility-test--wait-for-text child "__P3_INPUT__78")
          (p3-eat-feasibility-test--assert-terminal-metadata child)
          ;; Cursor/alternate-screen output belongs only to the Eat child, not
          ;; to Eshell's normal scrollback buffer.
          (with-current-buffer parent
            (goto-char (point-min))
            (should-not (search-forward "__P3_CURSOR__" nil t))
            (goto-char (point-min))
            (should-not (search-forward "__P3_TTY__" nil t)))
          (should (p3/project-shell-live-p parent)))
      (remove-hook 'eat-exec-hook #'p3/project-shell-eat-visual-buffer-setup)
      (eat-eshell-visual-command-mode -1)
      (dolist (buffer (list child parent))
        (when (buffer-live-p buffer)
          (let ((kill-buffer-query-functions nil))
            (kill-buffer buffer)))))))

(ert-deftest p3-eat-feasibility-dedicated-buffer-preserves-multiline-bracketed-paste ()
  (when (eq system-type 'windows-nt)
    (ert-skip "Native Windows full-screen TUI/PTY behavior is out of scope"))
  (p3-terminal-test-support-prepare-platform)
  (let ((root (file-name-as-directory temporary-file-directory))
        (p3/project-shell-buffers (make-hash-table :test #'equal))
        parent child)
    (unwind-protect
        (cl-letf (((symbol-function 'p3/project-shell-root) (lambda () root)))
          (eat-eshell-visual-command-mode 1)
          (add-hook 'eat-exec-hook #'p3/project-shell-eat-visual-buffer-setup)
          (setq parent (p3/project-shell-buffer))
          (setq child
                (p3-eat-feasibility-test--start-visual-fixture
                 parent 7 "paste"))
          ;; Waiting for the cursor marker also ensures Eat has processed the
          ;; fixture's bracketed-paste enable sequence before the yank.
          (p3-eat-feasibility-test--wait-for-text child "__P3_CURSOR__")
          (kill-new "alpha\nbeta")
          (with-current-buffer child
            (eat-yank))
          (p3-eat-feasibility-test--wait-for-process-exit child)
          (p3-eat-feasibility-test--wait-for-text child "__P3_PASTE__")
          (with-current-buffer child
            (goto-char (point-min))
            (should
             (re-search-forward
              "__P3_PASTE__1b5b3230307e616c7068610a626574611b5b3230317e"
              nil t)))
          (with-current-buffer parent
            (goto-char (point-min))
            (should-not (search-forward "alpha" nil t))
            (goto-char (point-min))
            (should-not (search-forward "__P3_PASTE__" nil t))))
      (remove-hook 'eat-exec-hook #'p3/project-shell-eat-visual-buffer-setup)
      (eat-eshell-visual-command-mode -1)
      (dolist (buffer (list child parent))
        (when (buffer-live-p buffer)
          (let ((kill-buffer-query-functions nil))
            (kill-buffer buffer)))))))

(ert-deftest p3-eat-feasibility-successful-visual-command-returns-to-project-eshell ()
  (when (eq system-type 'windows-nt)
    (ert-skip "Native Windows full-screen TUI/PTY behavior is out of scope"))
  (p3-terminal-test-support-prepare-platform)
  (let ((root (file-name-as-directory temporary-file-directory))
        (p3/project-shell-buffers (make-hash-table :test #'equal))
        parent child)
    (unwind-protect
        (cl-letf (((symbol-function 'p3/project-shell-root) (lambda () root)))
          (eat-eshell-visual-command-mode 1)
          (add-hook 'eat-exec-hook #'p3/project-shell-eat-visual-buffer-setup)
          (setq parent (p3/project-shell-buffer))
          (switch-to-buffer parent)
          (setq child
                (p3-eat-feasibility-test--start-visual-fixture parent 0))
          (p3-eat-feasibility-test--wait-for-text child "__P3_CURSOR__")
          (process-send-string (get-buffer-process child) "x")
          (let ((deadline (+ (float-time) 5.0)))
            (while (and (buffer-live-p child) (< (float-time) deadline))
              (accept-process-output nil 0.05)))
          (should-not (buffer-live-p child))
          (should (p3/project-shell-live-p parent))
          (should (eq (window-buffer (selected-window)) parent))
          (should (eq parent (p3/project-shell-buffer))))
      (remove-hook 'eat-exec-hook #'p3/project-shell-eat-visual-buffer-setup)
      (eat-eshell-visual-command-mode -1)
      (when (buffer-live-p child)
        (let ((kill-buffer-query-functions nil)) (kill-buffer child)))
      (when (buffer-live-p parent)
        (let ((kill-buffer-query-functions nil)) (kill-buffer parent))))))

(ert-deftest p3-eat-feasibility-windows-project-shell-runs-normal-cli-tools ()
  (unless (eq system-type 'windows-nt)
    (ert-skip "Native Windows-only ordinary CLI contract"))
  (p3-terminal-test-support-prepare-platform)
  (should (executable-find "git"))
  (should (executable-find "bash"))
  (let* ((raw-root (make-temp-file "p3-windows-eshell-" t))
         (root (p3/project-normalize-root raw-root))
         (p3/project-shell-buffers (make-hash-table :test #'equal))
         buffer)
    (unwind-protect
        (cl-letf (((symbol-function 'p3/project-shell-root) (lambda () root)))
          (eat-eshell-visual-command-mode 1)
          (setq buffer (p3/project-shell-buffer))
          (with-current-buffer buffer
            (should (derived-mode-p 'eshell-mode))
            (should (equal p3/project-shell-root-value root))
            (should (equal (p3/project-normalize-root default-directory) root)))
          (p3-eat-feasibility-test--run-command
           buffer "git --version" "git version")
          (p3-eat-feasibility-test--run-command
           buffer "bash --version" "GNU bash")
          (should (p3/project-shell-live-p buffer))
          (should (eq buffer (p3/project-shell-buffer))))
      (eat-eshell-visual-command-mode -1)
      (when (and buffer (buffer-live-p buffer))
        (let ((kill-buffer-query-functions nil))
          (kill-buffer buffer)))
      (delete-directory raw-root t))))
