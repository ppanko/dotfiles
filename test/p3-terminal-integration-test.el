;;; p3-terminal-integration-test.el --- Project shell lifecycle tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'subr-x)
(require 'eshell)

(defconst p3-terminal-integration-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(add-to-list 'load-path
             (expand-file-name "lisp" p3-terminal-integration-test--root))

(require 'p3-terminal)

(ert-deftest p3-terminal-extra-first-does-not-claim-primary-name ()
  (let ((p3/project-shell-buffers (make-hash-table :test #'equal))
        (root (file-name-as-directory
               (expand-file-name "p3-extra-first" temporary-file-directory)))
        created)
    (unwind-protect
        (cl-letf (((symbol-function 'p3/project-shell-root) (lambda () root))
                  ((symbol-function 'p3/project-shell--start)
                   (lambda (name _root)
                     (let ((buffer (get-buffer-create name)))
                       (with-current-buffer buffer
                         (eshell-mode))
                       (push buffer created)
                       buffer))))
          (let ((extra (p3/project-shell-buffer t))
                (primary (p3/project-shell-buffer)))
            (should-not (eq extra primary))
            (should-not (equal (buffer-name extra) (buffer-name primary)))
            (should (string-match-p ":extra" (buffer-name extra)))
            (should (equal (buffer-name primary)
                           (p3/project-shell-buffer-name root)))
            (should (eq primary (gethash root p3/project-shell-buffers)))))
      (mapc (lambda (buffer)
              (when (buffer-live-p buffer)
                (kill-buffer buffer)))
            created))))

(ert-deftest p3-terminal-shell-root-stays-project-owned-after-directory-change ()
  (let* ((project (make-temp-file "p3-shell-project-" t))
         (elsewhere (make-temp-file "p3-shell-elsewhere-" t))
         (canonical (p3/project-normalize-root project))
         (buffer (generate-new-buffer " *p3-shell-root-test*")))
    (unwind-protect
        (with-current-buffer buffer
          (eshell-mode)
          (setq-local p3/project-shell-root-value canonical)
          (setq default-directory (file-name-as-directory elsewhere))
          (cl-letf (((symbol-function 'p3/project-root)
                     (lambda (&optional _error-on-unavailable)
                       (ert-fail "Stored shell root should be authoritative"))))
            (should (equal (p3/project-shell-root) canonical))))
      (when (buffer-live-p buffer)
        (kill-buffer buffer))
      (delete-directory project t)
      (delete-directory elsewhere t))))

(defun p3-terminal-integration-test--send-command (buffer command)
  "Insert COMMAND at BUFFER's Eshell prompt and execute it."
  (with-current-buffer buffer
    (goto-char (point-max))
    (insert command)
    (eshell-send-input)))

(defun p3-terminal-integration-test--run-command-for-output
    (buffer command regexp)
  "Run COMMAND in BUFFER and require REGEXP in its Eshell output."
  (with-current-buffer buffer
    (let ((start (point-max))
          (deadline (+ (float-time) 5.0))
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
      (should found)
      (let ((reap-deadline (+ (float-time) 5.0)))
        (while (and (eshell-head-process)
                    (< (float-time) reap-deadline))
          (accept-process-output (eshell-head-process) 0.05))
        (should-not (eshell-head-process))))))

(ert-deftest p3-terminal-real-eshell-starts-at-project-root ()
  (let* ((raw-root (make-temp-file "p3-real-eshell-" t))
         (root (p3/project-normalize-root raw-root))
         (p3/project-shell-buffers (make-hash-table :test #'equal))
         buffer)
    (unwind-protect
        (cl-letf (((symbol-function 'p3/project-root)
                   (lambda (&optional _error-on-unavailable) raw-root)))
          (setq buffer (p3/project-shell-buffer))
          (with-current-buffer buffer
            (should (derived-mode-p 'eshell-mode))
            (should (equal (p3/project-normalize-root default-directory) root))
            (should (equal p3/project-shell-root-value root))))
      (when (buffer-live-p buffer)
        (kill-buffer buffer))
      (delete-directory raw-root t))))

(ert-deftest p3-terminal-idle-primary-remains-reusable ()
  (let ((p3/project-shell-buffers (make-hash-table :test #'equal))
        (root (file-name-as-directory temporary-file-directory)))
    (cl-letf (((symbol-function 'p3/project-shell-root) (lambda () root)))
      (let ((first (p3/project-shell-buffer)))
        (unwind-protect
            (progn
              (should-not (get-buffer-process first))
              (should (p3/project-shell-live-p first))
              (should (eq first (p3/project-shell-buffer))))
          (kill-buffer first))))))

(ert-deftest p3-terminal-external-process-exit-keeps-project-shell-live ()
  (let ((p3/project-shell-buffers (make-hash-table :test #'equal))
        (root (file-name-as-directory temporary-file-directory)))
    (cl-letf (((symbol-function 'p3/project-shell-root) (lambda () root)))
      (let ((buffer (p3/project-shell-buffer)))
        (unwind-protect
            (progn
              (p3-terminal-integration-test--send-command buffer "git --version")
              (with-current-buffer buffer
                (let ((deadline (+ (float-time) 5.0))
                      process)
                  (while (and (setq process (eshell-head-process))
                              (< (float-time) deadline))
                    (accept-process-output process 0.05))))
              (should (p3/project-shell-live-p buffer))
              (should (eq buffer (p3/project-shell-buffer))))
          (kill-buffer buffer))))))

(ert-deftest p3-terminal-line-oriented-codex-and-pacman-output-stays-in-eshell ()
  (unless (eq system-type 'gnu/linux)
    (ert-skip "Fake executable regression uses POSIX shell scripts"))
  (let* ((raw-root (make-temp-file "p3-line-output-" t))
         (root (p3/project-normalize-root raw-root))
         (codex (expand-file-name "codex" raw-root))
         (pacman (expand-file-name "pacman" raw-root))
         (process-environment (copy-sequence process-environment))
         (exec-path (cons raw-root exec-path))
         (p3/project-shell-buffers (make-hash-table :test #'equal))
         buffer)
    (unwind-protect
        (progn
          (with-temp-file codex
            (insert "#!/bin/sh\nprintf '%s\\n' '__P3_CODEX_VERSION__'\n"))
          (with-temp-file pacman
            (insert "#!/bin/sh\nprintf '%s\\n' '__P3_PACMAN_QUERY__'\n"))
          (set-file-modes codex #o755)
          (set-file-modes pacman #o755)
          (setenv "PATH"
                  (concat raw-root path-separator (or (getenv "PATH") "")))
          (cl-letf (((symbol-function 'p3/project-shell-root) (lambda () root)))
            (setq buffer (p3/project-shell-buffer))
            ;; These successful commands used to be routed into transient Eat
            ;; buffers and disappear on exit 0.  Their output must live in the
            ;; parent Eshell scrollback instead.
            (p3-terminal-integration-test--run-command-for-output
             buffer "codex --version" "__P3_CODEX_VERSION__")
            (p3-terminal-integration-test--run-command-for-output
             buffer "pacman -Q" "__P3_PACMAN_QUERY__")
            (should (p3/project-shell-live-p buffer))))
      (when (and buffer (buffer-live-p buffer))
        (kill-buffer buffer))
      (delete-directory raw-root t))))

(ert-deftest p3-terminal-killing-primary-clears-root-mapping ()
  (let ((p3/project-shell-buffers (make-hash-table :test #'equal))
        (root (file-name-as-directory temporary-file-directory)))
    (cl-letf (((symbol-function 'p3/project-shell-root) (lambda () root)))
      (let ((buffer (p3/project-shell-buffer)))
        (should (eq buffer (gethash root p3/project-shell-buffers)))
        (kill-buffer buffer)
        (should-not (gethash root p3/project-shell-buffers))))))

(provide 'p3-terminal-integration-test)

;;; p3-terminal-integration-test.el ends here
