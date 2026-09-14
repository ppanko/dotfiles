;;; p3-terminal-integration-test.el --- Project shell lifecycle tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'subr-x)

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
                  ((symbol-function 'p3/project-shell-live-p)
                   (lambda (buffer) (buffer-live-p buffer)))
                  ((symbol-function 'p3/project-shell--start)
                   (lambda (name _root)
                     (let ((buffer (get-buffer-create name)))
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
          (setq-local p3/project-shell-root-value canonical)
          (setq default-directory (file-name-as-directory elsewhere))
          (cl-letf (((symbol-function 'p3/project-root)
                     (lambda ()
                       (ert-fail "Stored shell root should be authoritative"))))
            (should (equal (p3/project-shell-root) canonical))))
      (when (buffer-live-p buffer)
        (kill-buffer buffer))
      (delete-directory project t)
      (delete-directory elsewhere t))))

(defun p3-terminal-integration-test--reported-pwd (buffer process)
  "Return the working directory reported by PROCESS in BUFFER."
  (process-send-string
   process
   "printf '%s%s%s\\n' '__P3_' 'PWD__' \"$(if command -v cygpath >/dev/null 2>&1; then cygpath -aw \"$PWD\"; else pwd; fi)\"\n")
  (let ((deadline (+ (float-time) 10.0))
        reported)
    (while (and (not reported) (< (float-time) deadline))
      (accept-process-output process 0.1)
      (with-current-buffer buffer
        (save-excursion
          (goto-char (point-min))
          (when (re-search-forward "__P3_PWD__\\([^\r\n]+\\)" nil t)
            (setq reported (match-string-no-properties 1))))))
    reported))

(ert-deftest p3-terminal-real-bash-process-starts-at-project-root ()
  (let* ((raw-root (make-temp-file "p3-real-shell-" t))
         (root (p3/project-normalize-root raw-root))
         (p3/project-shell-buffers (make-hash-table :test #'equal))
         (msys-root (getenv "P3_TEST_MSYS2_ROOT"))
         (linuxy-environment-path
          (if (eq system-type 'windows-nt)
              (and msys-root
                   (file-name-as-directory
                    (expand-file-name "usr/bin" msys-root)))
            linuxy-environment-path))
         (shell-file-name shell-file-name)
         (explicit-shell-file-name explicit-shell-file-name)
         (explicit-bash.exe-args
          (and (boundp 'explicit-bash.exe-args) explicit-bash.exe-args))
         (shell-mode-hook shell-mode-hook)
         (process-environment (copy-sequence process-environment))
         buffer
         process)
    (unwind-protect
        (progn
          (when (eq system-type 'windows-nt)
            (unless msys-root
              (ert-skip "P3_TEST_MSYS2_ROOT is required for Windows shell smoke"))
            (p3/windows-configure-shell))
          (unless (or (eq system-type 'windows-nt) (executable-find "bash"))
            (ert-skip "Bash is unavailable for real shell smoke"))
          (cl-letf (((symbol-function 'p3/project-root) (lambda () raw-root)))
            (setq buffer (p3/project-shell-buffer)))
          (setq process (get-buffer-process buffer))
          (should (process-live-p process))
          (let ((reported
                 (p3-terminal-integration-test--reported-pwd buffer process)))
            (should reported)
            (setq reported
                  (replace-regexp-in-string
                   "\\\\" "/" (string-trim reported)))
            (should (equal (p3/project-normalize-root reported) root))))
      (when (and process (process-live-p process))
        (delete-process process))
      (when (and buffer (buffer-live-p buffer))
        (let ((kill-buffer-query-functions nil))
          (kill-buffer buffer)))
      (delete-directory raw-root t))))

(provide 'p3-terminal-integration-test)

;;; p3-terminal-integration-test.el ends here
