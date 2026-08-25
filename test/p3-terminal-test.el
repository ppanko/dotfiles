;;; p3-terminal-test.el --- Tests for p3-terminal -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(defconst p3-terminal-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(add-to-list 'load-path (expand-file-name "lisp" p3-terminal-test--root))

(require 'p3-core)
(require 'p3-terminal)

(ert-deftest p3-terminal-buffer-name-is-stable-and-root-specific ()
  (let ((first (p3/vterm-buffer-name "/tmp/project-a/"))
        (again (p3/vterm-buffer-name "/tmp/project-a/"))
        (second (p3/vterm-buffer-name "/tmp/project-b/")))
    (should (equal first again))
    (should-not (equal first second))
    (should (string-match-p "\\`\\*vterm:project-a:[[:xdigit:]]\\{6\\}\\*\\'" first))))

(ert-deftest p3-terminal-root-prefers-project-root ()
  (let ((default-directory "/tmp/fallback/"))
    (cl-letf (((symbol-function 'p3/project-root)
               (lambda () "/tmp/project/")))
      (should (equal (p3/vterm-root) "/tmp/project/")))))

(ert-deftest p3-terminal-root-falls-back-to-default-directory ()
  (let ((default-directory "/tmp/fallback/"))
    (cl-letf (((symbol-function 'p3/project-root) (lambda () nil)))
      (should (equal (p3/vterm-root) "/tmp/fallback/")))))

(ert-deftest p3-terminal-command-map-exposes-session-workflow ()
  (dolist (key '("t" "n" "s" "o" "f" "r" "c" "k"))
    (should (commandp (keymap-lookup p3/vterm-command-map key)))))

(ert-deftest p3-terminal-windows-setup-is-noop-off-windows ()
  (let ((system-type 'gnu/linux)
        (shell-file-name "unchanged-shell")
        (explicit-shell-file-name "unchanged-explicit"))
    (p3/terminal-configure-windows-shell)
    (should (equal shell-file-name "unchanged-shell"))
    (should (equal explicit-shell-file-name "unchanged-explicit"))))

(ert-deftest p3-terminal-windows-setup-selects-rtools-shells ()
  (let* ((root (make-temp-file "p3-terminal-test-" t))
         (linuxy-environment-path (file-name-as-directory root))
         (bash (expand-file-name "bash.exe" root))
         (zsh (expand-file-name "zsh.exe" root))
         (system-type 'windows-nt)
         (global-map (copy-keymap global-map))
         (shell-file-name "old-shell")
         (explicit-shell-file-name nil)
         (explicit-bash.exe-args nil)
         (old-shell-environment (getenv "SHELL")))
    (unwind-protect
        (progn
          (with-temp-file bash)
          (with-temp-file zsh)
          (p3/terminal-configure-windows-shell)
          (should (equal shell-file-name bash))
          (should (equal explicit-shell-file-name zsh))
          (should (equal explicit-bash.exe-args '("--login")))
          (should (equal (getenv "SHELL") bash))
          (should (eq (key-binding (kbd "C-x C-u")) #'shell)))
      (setenv "SHELL" old-shell-environment)
      (delete-directory root t))))

(ert-deftest p3-terminal-windows-shell-strips-carriage-returns ()
  (with-temp-buffer
    (let (coding-call)
      (cl-letf (((symbol-function 'get-buffer-process)
                 (lambda (&optional _buffer) 'fake-process))
                ((symbol-function 'set-process-coding-system)
                 (lambda (&rest arguments)
                   (setq coding-call arguments))))
        (p3/windows-shell-mode-setup)
        (should (memq #'comint-strip-ctrl-m comint-output-filter-functions))
        (should (equal coding-call
                       '(fake-process utf-8-unix utf-8-unix)))))))

(provide 'p3-terminal-test)

;;; p3-terminal-test.el ends here
