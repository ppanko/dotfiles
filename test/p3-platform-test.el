;;; p3-platform-test.el --- Tests for p3-platform -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(defconst p3-platform-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(add-to-list 'load-path (expand-file-name "lisp" p3-platform-test--root))

(require 'p3-platform)

(ert-deftest p3-platform-rtools-version-parses-versioned-directory ()
  (should (= (p3/windows-rtools-version "C:/rtools45") 45))
  (should (= (p3/windows-rtools-version "C:/RTOOLS46/") 46))
  (should-not (p3/windows-rtools-version "C:/rtools")))

(ert-deftest p3-platform-rtools-setup-populates-compatible-paths ()
  (let* ((root (make-temp-file "p3-platform-rtools-" t))
         (usr-bin (expand-file-name "usr/bin" root))
         (toolchain (expand-file-name "x86_64-w64-mingw32.static.posix/bin" root))
         (dictionary-directory (expand-file-name "usr/share/hunspell" root))
         (bash (expand-file-name "bash.exe" usr-bin))
         (hunspell (expand-file-name "hunspell.exe" usr-bin))
         (p3/windows-rtools-override nil)
         (rtools-path nil)
         (linuxy-environment-path nil)
         (mingw64-path nil)
         (p3/windows-hunspell-program nil)
         (p3/windows-hunspell-dictionary-directory nil)
         (exec-path nil)
         (old-path (getenv "PATH")))
    (unwind-protect
        (progn
          (make-directory usr-bin t)
          (make-directory toolchain t)
          (make-directory dictionary-directory t)
          (with-temp-file bash)
          (with-temp-file hunspell)
          (setenv "PATH" "fallback")
          (cl-letf (((symbol-function 'p3/windows-latest-rtools)
                     (lambda () root)))
            (let ((system-type 'windows-nt))
              (p3/windows-configure-rtools)))
          (should (equal rtools-path (directory-file-name root)))
          (should (equal linuxy-environment-path
                         (file-name-as-directory usr-bin)))
          (should (equal mingw64-path
                         (file-name-as-directory toolchain)))
          (should (equal p3/windows-hunspell-program hunspell))
          (should (equal p3/windows-hunspell-dictionary-directory
                         dictionary-directory))
          (should (equal (car exec-path)
                         (file-name-as-directory usr-bin)))
          (should (string-prefix-p (directory-file-name usr-bin)
                                   (getenv "PATH"))))
      (setenv "PATH" old-path)
      (delete-directory root t))))

(ert-deftest p3-platform-windows-shell-selects-rtools-shells ()
  (let* ((root (make-temp-file "p3-platform-shell-" t))
         (linuxy-environment-path (file-name-as-directory root))
         (bash (expand-file-name "bash.exe" root))
         (zsh (expand-file-name "zsh.exe" root))
         (old-shell-environment (getenv "SHELL"))
         (bash-args-was-bound (boundp 'explicit-bash.exe-args))
         (old-bash-args (and bash-args-was-bound
                             (symbol-value 'explicit-bash.exe-args))))
    (unwind-protect
        (progn
          (with-temp-file bash)
          (with-temp-file zsh)
          (set 'explicit-bash.exe-args nil)
          (let ((system-type 'windows-nt)
                (global-map (copy-keymap global-map))
                (shell-file-name "old-shell")
                (explicit-shell-file-name nil))
            (p3/windows-configure-shell)
            (should (equal shell-file-name bash))
            (should (equal explicit-shell-file-name zsh))
            (should (equal (symbol-value 'explicit-bash.exe-args)
                           '("--login")))
            (should (equal (getenv "SHELL") bash))
            (should (eq (key-binding (kbd "C-x C-u")) #'shell))))
      (setenv "SHELL" old-shell-environment)
      (if bash-args-was-bound
          (set 'explicit-bash.exe-args old-bash-args)
        (makunbound 'explicit-bash.exe-args))
      (delete-directory root t))))

(ert-deftest p3-platform-windows-shell-strips-carriage-returns ()
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

(ert-deftest p3-platform-r-program-prefers-valid-override ()
  (let* ((root (make-temp-file "p3-platform-r-" t))
         (program (expand-file-name "Rterm.exe" root))
         (p3/windows-r-program-override program))
    (unwind-protect
        (progn
          (with-temp-file program)
          (cl-letf (((symbol-function 'p3/windows-latest-r-program)
                     (lambda () (ert-fail "Auto-discovery should not run"))))
            (should (equal (p3/windows-select-r-program) program))))
      (delete-directory root t))))

(ert-deftest p3-platform-setup-is-noop-off-windows ()
  (let ((system-type 'gnu/linux)
        (called nil))
    (cl-letf (((symbol-function 'p3/windows-configure-rtools)
               (lambda () (setq called t)))
              ((symbol-function 'p3/windows-configure-r-program)
               (lambda () (setq called t)))
              ((symbol-function 'p3/windows-configure-shell)
               (lambda () (setq called t))))
      (p3/platform-setup)
      (should-not called))))

(provide 'p3-platform-test)

;;; p3-platform-test.el ends here
