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
          (setenv "HISTFILE" nil)
          (cl-letf (((symbol-function 'p3/project-root)
                     (lambda (&optional _error-on-unavailable) raw-root)))
            (setq buffer (p3/project-shell-buffer)))
          (setq process (get-buffer-process buffer))
          (should (process-live-p process))
          (with-current-buffer buffer
            (should (equal shell--start-prog
                           (if (eq system-type 'windows-nt) "bash.exe" "bash")))
            (should (string-suffix-p ".bash_history"
                                     comint-input-ring-file-name)))
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

(ert-deftest p3-terminal-windows-resyncs-after-shell-directory-change ()
  (unless (eq system-type 'windows-nt)
    (ert-skip "Native Windows-only MSYS directory resync regression"))
  (let* ((msys-root (getenv "P3_TEST_MSYS2_ROOT"))
         (raw-root (make-temp-file "p3-windows-resync-" t))
         (child (expand-file-name "child" raw-root))
         (root (p3/project-normalize-root raw-root))
         (linuxy-environment-path
          (and msys-root
               (file-name-as-directory
                (expand-file-name "usr/bin" msys-root))))
         (shell-file-name shell-file-name)
         (explicit-shell-file-name explicit-shell-file-name)
         (explicit-bash.exe-args
          (and (boundp 'explicit-bash.exe-args) explicit-bash.exe-args))
         (shell-mode-hook shell-mode-hook)
         (process-environment (copy-sequence process-environment))
         (name "*p3-windows-resync-shell-test*")
         buffer
         process)
    (unless msys-root
      (ert-skip "P3_TEST_MSYS2_ROOT is required for Windows shell smoke"))
    (make-directory child)
    (unwind-protect
        (progn
          (p3/windows-configure-shell)
          (setq buffer (p3/project-shell--start name root)
                process (get-buffer-process buffer))
          (should (process-live-p process))
          (process-send-string process "cd child\nprintf '__P3_CD_READY__\\n'\n")
          (let ((deadline (+ (float-time) 10.0))
                ready)
            (while (and (not ready) (< (float-time) deadline))
              (accept-process-output process 0.1)
              (with-current-buffer buffer
                (save-excursion
                  (goto-char (point-min))
                  (setq ready (re-search-forward "__P3_CD_READY__" nil t)))))
            (should ready))
          (with-current-buffer buffer
            (shell-resync-dirs)
            (should (equal (p3/project-normalize-root default-directory)
                           (p3/project-normalize-root child)))))
      (when (and process (process-live-p process))
        (delete-process process))
      (when (and buffer (buffer-live-p buffer))
        (let ((kill-buffer-query-functions nil))
          (kill-buffer buffer)))
      (delete-directory raw-root t))))

(ert-deftest p3-terminal-start-enables-shared-rich-input-ux ()
  (let* ((root (file-name-as-directory
                (expand-file-name "p3-rich-shell" temporary-file-directory)))
         (name "*p3-rich-shell-test*")
         captured-fontify
         captured-undef
         captured-prompt
         captured-bash-args)
    (unwind-protect
        (cl-letf (((symbol-function 'p3/windows-p) (lambda () nil))
                  ((symbol-function 'p3/platform-bash-program)
                   (lambda () "/bin/bash"))
                  ((symbol-function 'shell)
                   (lambda (buffer-name &optional _file-name)
                     (setq captured-fontify shell-fontify-input-enable
                           captured-undef shell-highlight-undef-enable
                           captured-prompt shell-prompt-pattern
                           captured-bash-args explicit-bash-args)
                     (with-current-buffer (get-buffer-create buffer-name)
                       (shell-mode)
                       (current-buffer))))
                  ((symbol-function 'shell-eval-command) #'ignore))
          (let ((buffer (p3/project-shell--start name root)))
            (should captured-fontify)
            (should captured-undef)
            (should (equal captured-bash-args '("--noediting" "-i")))
            (should (string-match-p "❯" captured-prompt))
            (with-current-buffer buffer
              (should comint-input-ignoredups)
              (should (eq (key-binding (kbd "C-r"))
                          #'comint-history-isearch-backward)))))
      (when-let ((buffer (get-buffer name)))
        (kill-buffer buffer)))))

(ert-deftest p3-terminal-start-configures-shared-starship-prompt-with-fallback ()
  (let* ((root (file-name-as-directory
                (expand-file-name "p3-starship-shell" temporary-file-directory)))
         (name "*p3-starship-shell-test*")
         (outer-starship-config (getenv "STARSHIP_CONFIG"))
         captured-config
         captured-init)
    (unwind-protect
        (cl-letf (((symbol-function 'p3/windows-p) (lambda () nil))
                  ((symbol-function 'p3/platform-bash-program)
                   (lambda () "/bin/bash"))
                  ((symbol-function 'shell)
                   (lambda (buffer-name &optional _file-name)
                     (setq captured-config (getenv "STARSHIP_CONFIG"))
                     (with-current-buffer (get-buffer-create buffer-name)
                       (shell-mode)
                       (current-buffer))))
                  ((symbol-function 'shell-eval-command)
                   (lambda (command)
                     (setq captured-init command))))
          (p3/project-shell--start name root)
          (should captured-config)
          (should (file-readable-p captured-config))
          (should (string-suffix-p "templates/p3-starship.toml"
                                   (subst-char-in-string ?\\ ?/ captured-config)))
          (should (string-match-p
                   "starship init bash --print-full-init" captured-init))
          (should (string-match-p "PS1=.*❯" captured-init))
          (should (string-suffix-p "\n" captured-init))
          (should (equal (getenv "STARSHIP_CONFIG") outer-starship-config)))
      (when-let ((buffer (get-buffer name)))
        (kill-buffer buffer)))))

(ert-deftest p3-terminal-linux-starship-present-uses-rich-comint-term ()
  (unless (eq system-type 'gnu/linux)
    (ert-skip "GNU/Linux-only Comint TERM regression"))
  (unless (executable-find "bash")
    (ert-skip "Bash is unavailable for Starship success smoke"))
  (let* ((raw-root (make-temp-file "p3-starship-success-" t))
         (root (p3/project-normalize-root raw-root))
         (fake-bin (expand-file-name "bin" raw-root))
         (fake-starship (expand-file-name "starship" fake-bin))
         (name "*p3-starship-success-shell-test*")
         (shell-file-name shell-file-name)
         (explicit-shell-file-name explicit-shell-file-name)
         (shell-mode-hook shell-mode-hook)
         (process-environment (copy-sequence process-environment))
         buffer
         process)
    (make-directory fake-bin)
    (with-temp-file fake-starship
      (insert "#!/bin/sh\n"
              "if [ \"$1\" = init ] && [ \"$2\" = bash ] && [ \"$3\" = --print-full-init ]; then\n"
              "  printf '%s\\n' \"PS1='STARSHIP_OK ❯ '\"\n"
              "  exit 0\n"
              "fi\n"
              "exit 1\n"))
    (set-file-modes fake-starship #o755)
    (setenv "PATH" (concat fake-bin path-separator (or (getenv "PATH") "")))
    (unwind-protect
        (progn
          (setq buffer (p3/project-shell--start name root)
                process (get-buffer-process buffer))
          (should (process-live-p process))
          (process-send-string
           process
           "printf '%s%s%s\\n' '__P3_' 'TERM__' \"$TERM\"; printf '%s%s%s\\n' '__P3_' 'PS1__' \"$PS1\"\n")
          (let ((deadline (+ (float-time) 10.0))
                reported-term
                reported-ps1)
            (while (and (not (and reported-term reported-ps1))
                        (< (float-time) deadline))
              (accept-process-output process 0.1)
              (with-current-buffer buffer
                (save-excursion
                  (goto-char (point-min))
                  (when (re-search-forward "__P3_TERM__\\([^\r\n]+\\)" nil t)
                    (setq reported-term (match-string-no-properties 1)))
                  (goto-char (point-min))
                  (when (re-search-forward "__P3_PS1__\\([^\r\n]+\\)" nil t)
                    (setq reported-ps1 (match-string-no-properties 1))))))
            (should (equal reported-term "dumb-emacs-ansi"))
            (should (equal reported-ps1 "STARSHIP_OK ❯ "))))
      (when (and process (process-live-p process))
        (delete-process process))
      (when (and buffer (buffer-live-p buffer))
        (let ((kill-buffer-query-functions nil))
          (kill-buffer buffer)))
      (delete-directory raw-root t))))

(ert-deftest p3-terminal-starship-init-failure-uses-fallback-prompt ()
  (let* ((raw-root (make-temp-file "p3-starship-fallback-" t))
         (root (p3/project-normalize-root raw-root))
         (name "*p3-starship-fallback-shell-test*")
         (msys-root (getenv "P3_TEST_MSYS2_ROOT"))
         (linuxy-environment-path
          (if (eq system-type 'windows-nt)
              (and msys-root
                   (file-name-as-directory
                    (expand-file-name "usr/bin" msys-root)))
            linuxy-environment-path))
         (shell-file-name shell-file-name)
         (explicit-shell-file-name explicit-shell-file-name)
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
            (ert-skip "Bash is unavailable for Starship fallback smoke"))
          (setq buffer (p3/project-shell--start name root)
                process (get-buffer-process buffer))
          (should (process-live-p process))
          (process-send-string
           process
           (concat
            "starship() { return 1; }\n"
            "unset -f starship_precmd 2>/dev/null || true\n"
            p3/project-shell-prompt-init-command
            "printf '%s%s%s\\n' '__P3_' 'PS1__' \"$PS1\"\n"))
          (let ((deadline (+ (float-time) 10.0))
                reported)
            (while (and (not reported) (< (float-time) deadline))
              (accept-process-output process 0.1)
              (with-current-buffer buffer
                (save-excursion
                  (goto-char (point-min))
                  (when (re-search-forward "__P3_PS1__\\([^\r\n]+\\)" nil t)
                    (setq reported (match-string-no-properties 1))))))
            (should reported)
            (should (equal reported "\\w ❯ "))))
      (when (and process (process-live-p process))
        (delete-process process))
      (when (and buffer (buffer-live-p buffer))
        (let ((kill-buffer-query-functions nil))
          (kill-buffer buffer)))
      (delete-directory raw-root t))))

(ert-deftest p3-terminal-starship-config-has-unified-paths-and-spacing ()
  (with-temp-buffer
    (insert-file-contents (p3/project-shell-starship-config))
    (let ((config (buffer-string)))
      (should (string-match-p "^format = .* \\$character\"$" config))
      (should (string-match-p "^use_os_path_sep = false$" config))
      (should
       (string-match-p
        (concat "^" (regexp-quote "format = \"[$path]($style)\"") "$")
        config)))))

(provide 'p3-terminal-integration-test)

;;; p3-terminal-integration-test.el ends here